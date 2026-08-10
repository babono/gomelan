//
//  AudioEngineController.swift
//  gomelan
//
//  Ties the live mic to the detection pipeline:
//
//    mic tap → ring buffer → 1024/256 STFT → spectral flux → onset detection
//            → (wait ~105ms) → 4096 fingerprint → cosine match → strike
//
//  Two window sizes, deliberately. Onset detection uses 1024/256 because it needs
//  TIME precision and 43Hz frequency resolution is plenty. Fingerprinting uses
//  4096 because it needs FREQUENCY precision to resolve inharmonic partials, and
//  by then the strike time is already known so blurring across 93ms costs nothing.
//  A single shared window cannot serve both.
//
//  Strikes are therefore reported about 105ms after they physically happen. That
//  is not latency to be tuned away — the note has to sound before it can be
//  identified. `hostTime` is reconstructed from the sample index, so the reported
//  time is when the strike OCCURRED, not when this code got around to it.
//

import AVFoundation

final class AudioEngineController {

    /// Called on the main queue for each identified strike.
    var onStrike: ((_ keyIndex: Int, _ hostTime: Double, _ confidence: Double) -> Void)?

    /// Called on the main queue for each onset whose key could not be called —
    /// either no template won by enough margin, or nothing is calibrated yet.
    var onUnclearStrike: ((_ hostTime: Double) -> Void)?

    /// Called on the main queue for every onset, with the fingerprint that the
    /// calibration flow should store, plus a display-only pitch estimate.
    var onCalibrationStrike: ((_ fingerprint: [Float], _ fundamentalHz: Double, _ hostTime: Double) -> Void)?

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "gomelan.audio.dsp")

    private var config = DSPConfig()
    private var ring = SampleRing(capacity: 1)
    private var onsetFFT: FFTProcessor?
    private var fingerprintFFT: FFTProcessor?
    private var flux: SpectralFlux?
    private var detector: OnsetDetector?
    private var fingerprinter: Fingerprinter?
    private var classifier: KeyClassifier?

    /// Absolute index of the next STFT window's first sample.
    private var nextWindowStart = 0
    private var windowScratch: [Float] = []

    /// Onsets waiting for enough audio to fingerprint.
    private var pending: [OnsetDetector.Onset] = []

    /// Maps absolute sample index to the CACurrentMediaTime clock that PlayEngine
    /// judges against.
    private var anchorHostSeconds: Double?
    private var anchorSampleIndex = 0

    private(set) var isRunning = false

    // MARK: - Lifecycle

    func start(profile: InstrumentProfile) throws {
        guard !isRunning else { return }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate > 0 ? format.sampleRate : 44100

        // Prefer the settings the Python builder recorded; fall back to defaults.
        var newConfig = CalibrationFile.loadFromBundle()?.dspConfig(sampleRate: sampleRate)
            ?? DSPConfig()
        newConfig.sampleRate = sampleRate

        queue.sync {
            configure(with: newConfig, keys: profile.keys)
        }

        input.installTap(onBus: 0,
                         bufferSize: AVAudioFrameCount(1024),
                         format: format) { [weak self] buffer, when in
            self?.queue.async { self?.handle(buffer, when: when) }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    func resetDetector() {
        queue.async { [weak self] in
            guard let self else { return }
            self.ring.reset()
            self.flux?.reset()
            self.detector?.reset()
            self.pending.removeAll(keepingCapacity: true)
            self.nextWindowStart = 0
            self.anchorHostSeconds = nil
        }
    }

    func updateKeys(_ keys: [InstrumentKey]) {
        queue.async { [weak self] in self?.classifier?.updateKeys(keys) }
    }

    /// Worst-case similarity between calibrated keys. Want < 0.5.
    func separability(completion: @escaping ((worst: Double, mean: Double, pair: (Int, Int))?) -> Void) {
        queue.async { [weak self] in
            let result = self?.classifier?.separability()
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Setup

    private func configure(with newConfig: DSPConfig, keys: [InstrumentKey]) {
        config = newConfig

        let onsetFFT = FFTProcessor(size: config.onsetWindow)
        let fingerprintFFT = FFTProcessor(size: config.fpWindow)

        // Enough history for the fingerprint window, its pre-onset noise window,
        // refinement's backward search, and the detector's lookahead.
        let capacity = max(config.fpWindow * 4, Int(config.sampleRate * 2))
        ring = SampleRing(capacity: capacity)

        self.onsetFFT = onsetFFT
        self.fingerprintFFT = fingerprintFFT
        flux = SpectralFlux(config: config, fft: onsetFFT)
        fingerprinter = Fingerprinter(config: config, fft: fingerprintFFT)
        classifier = KeyClassifier(config: config, keys: keys)

        let detector = OnsetDetector(config: config)
        detector.sampleProvider = { [weak self] from, count, out in
            self?.ring.read(from: from, count: count, into: &out) ?? false
        }
        self.detector = detector

        windowScratch = [Float](repeating: 0, count: config.onsetWindow)
        nextWindowStart = 0
        pending.removeAll(keepingCapacity: true)
        anchorHostSeconds = nil
    }

    // MARK: - Processing (DSP queue)

    private func handle(_ buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        // Anchor the sample timeline to the host clock using the buffer's own
        // timestamp. Reading the clock later — after hopping to the main queue —
        // would fold dispatch latency into every reported strike time.
        if when.isHostTimeValid {
            anchorHostSeconds = AVAudioTime.seconds(forHostTime: when.hostTime)
            anchorSampleIndex = ring.totalWritten
        }

        ring.write(channel, count: frames)
        processAvailableWindows()
        drainPending()
    }

    private func processAvailableWindows() {
        guard let flux, let detector else { return }

        while nextWindowStart + config.onsetWindow <= ring.totalWritten {
            guard ring.read(from: nextWindowStart, count: config.onsetWindow, into: &windowScratch) else {
                // Fell behind the ring — skip ahead rather than emit nonsense.
                nextWindowStart = ring.oldestAvailable
                continue
            }
            let raw = flux.process(window: windowScratch)
            for onset in detector.append(flux: flux.normalised(raw)) {
                pending.append(onset)
            }
            nextWindowStart += config.onsetHop
        }
    }

    private func drainPending() {
        guard let fingerprinter, !pending.isEmpty else { return }

        var stillPending: [OnsetDetector.Onset] = []
        for onset in pending {
            let required = onset.sampleIndex + config.fingerprintLatencySamples
            if ring.totalWritten < required {
                stillPending.append(onset)   // not enough of the note has sounded yet
                continue
            }
            emit(onset, fingerprinter: fingerprinter)
        }
        pending = stillPending
    }

    private func emit(_ onset: OnsetDetector.Onset, fingerprinter: Fingerprinter) {
        let hostTime = hostSeconds(forSample: onset.sampleIndex)

        guard let vector = fingerprinter.fingerprint(onsetSample: onset.sampleIndex, ring: ring) else {
            DispatchQueue.main.async { [weak self] in self?.onUnclearStrike?(hostTime) }
            return
        }

        if onCalibrationStrike != nil {
            let hz = fingerprinter.topPeaks(onsetSample: onset.sampleIndex, ring: ring, count: 1)
                .first?.hz ?? 0
            DispatchQueue.main.async { [weak self] in
                self?.onCalibrationStrike?(vector, hz, hostTime)
            }
        }

        if let match = classifier?.classify(vector: vector) {
            DispatchQueue.main.async { [weak self] in
                self?.onStrike?(match.keyIndex, hostTime, match.confidence)
            }
        } else {
            DispatchQueue.main.async { [weak self] in self?.onUnclearStrike?(hostTime) }
        }
    }

    /// Absolute sample index → CACurrentMediaTime seconds.
    private func hostSeconds(forSample index: Int) -> Double {
        guard let anchor = anchorHostSeconds else { return CACurrentMediaTime() }
        return anchor + Double(index - anchorSampleIndex) / config.sampleRate
    }
}

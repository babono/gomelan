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

    /// Called on the main queue for every gated onset — a real strike happened at
    /// `hostTime`, regardless of which key. This is the trigger for the vision-first
    /// path: audio says *when*, vision decides *which key* from the frame at that
    /// time. Fires independently of the audio key classification above, so it works
    /// even when nothing is audio-calibrated.
    var onStrikeDetected: ((_ hostTime: Double) -> Void)?

    /// Diagnostic feed for the audio test screen. Reports EVERY onset the detector
    /// surfaces — including ones rejected by the amplitude gate — so the gate,
    /// noise floor and strike loudness are all visible. Only dispatched when a
    /// listener is attached, so it costs nothing in normal play.
    struct OnsetDebug {
        let hostTime: Double
        let amplitude: Float
        let gate: Float
        let passedGate: Bool
        let fingerprinted: Bool
    }
    var onOnsetDebug: ((OnsetDebug) -> Void)?

    /// Called on the main queue for every onset, with the fingerprint that the
    /// calibration flow should store, plus a display-only pitch estimate.
    var onCalibrationStrike: ((_ fingerprint: [Float], _ fundamentalHz: Double, _ hostTime: Double) -> Void)?

    /// One captured strike, with the loudness used to pick between candidates.
    struct CapturedStrike {
        let fingerprint: [Float]
        let fundamentalHz: Double
        let hostTime: Double
        let amplitude: Float
        /// Strongest partials (hz, relative strength), for the calibration debug
        /// readout only. Matching never looks at these.
        var topPartials: [(hz: Double, strength: Double)] = []
    }

    private struct Capture {
        let endSample: Int
        let completion: (CapturedStrike?) -> Void
        var best: CapturedStrike?
        var candidateCount = 0
        /// Whether the detector has been flushed at window end (see below).
        var flushed = false
    }
    private var capture: Capture?

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

    /// Loudest strike heard recently, for the relative half of the amplitude
    /// gate. Decays slowly so one hard hit does not deafen the app to the
    /// quieter playing that follows.
    private var strikeAmplitudePeak: Float = 0
    private let amplitudePeakDecay: Float = 0.995

    /// Maps absolute sample index to the CACurrentMediaTime clock that PlayEngine
    /// judges against.
    private var anchorHostSeconds: Double?
    private var anchorSampleIndex = 0

    /// Recent onset times (host seconds), for the vision path to snap its strike
    /// timing onto when a clean onset exists. Written on the DSP queue, read from
    /// the main actor, so guarded by a lock.
    private var recentOnsets: [Double] = []
    private let recentOnsetsLock = NSLock()

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
            self.strikeAmplitudePeak = 0
        }
    }

    func updateKeys(_ keys: [InstrumentKey]) {
        queue.async { [weak self] in self?.classifier?.updateKeys(keys) }
    }

    /// Listen for `duration` and report the STRONGEST strike heard, or nil if
    /// nothing was heard at all.
    ///
    /// Taking the loudest rather than the first is not a refinement — it is the
    /// only thing that makes calibration work. Real recordings produce 6-12
    /// onsets where there was one strike (handling noise, the mallet approach,
    /// room reflections, decay ripple), and no threshold setting separates them:
    /// swept thresh_mult 1.6-5.0 x thresh_floor 0.04-0.30 in Python and the
    /// spurious onsets stay flux-comparable to the real one. Amplitude does
    /// separate them cleanly — the true strike measured 3-10x every false
    /// positive across all five reference recordings.
    ///
    /// Mirrors `strongest_onset` in gamelan_dsp.py.
    func captureStrongestStrike(duration: TimeInterval,
                                completion: @escaping (CapturedStrike?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            // Start clean, then wait out the warm-up before the window opens.
            self.ring.reset()
            self.flux?.reset()
            self.detector?.reset()
            self.pending.removeAll(keepingCapacity: true)
            self.nextWindowStart = 0
            self.anchorHostSeconds = nil
            self.strikeAmplitudePeak = 0

            let samples = Int(duration * self.config.sampleRate)
            self.capture = Capture(endSample: samples, completion: completion)
        }
    }

    func cancelCapture() {
        queue.async { [weak self] in
            guard let self, let capture = self.capture else { return }
            self.capture = nil
            DispatchQueue.main.async { capture.completion(nil) }
        }
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
        finishCaptureIfDue()
    }

    /// Close the capture window once the last strike inside it has had time to be
    /// fingerprinted — otherwise a hit right at the end would be discarded.
    private func finishCaptureIfDue() {
        guard var current = capture else { return }

        // Once the listening window has fully elapsed, flush the onset detector so
        // a strike still held as its "best pending candidate" gets committed. The
        // detector only releases a held candidate when a LATER peak arrives after
        // it, so a clean single strike with nothing after it would otherwise never
        // be reported — which is why an isolated key seemed undetectable while a
        // noisier one worked. Fingerprint the flushed onset immediately if enough
        // audio exists; otherwise it waits in `pending` like any other.
        if !current.flushed && ring.totalWritten >= current.endSample {
            current.flushed = true
            capture = current
            if let flushed = detector?.flush(), !flushed.isEmpty {
                pending.append(contentsOf: flushed)
                drainPending()
            }
            return
        }

        let settled = current.endSample + config.fingerprintLatencySamples
        guard ring.totalWritten >= settled, pending.isEmpty else { return }

        capture = nil
        // Reject a capture whose loudest candidate is really just noise — a missed
        // or too-soft strike. Averaging one of these into a template wrecks it
        // (observed: an amp 0.002 "strike" scored 0.36 self-similarity against a
        // real hit at amp 1.1). Report nothing so the user strikes again.
        let best = current.best
        if let best, best.amplitude >= config.minStrikeAmplitude {
            DispatchQueue.main.async { current.completion(best) }
        } else {
            DispatchQueue.main.async { current.completion(nil) }
        }
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

    /// Loudest sample in the 60ms after an onset — how "real" the strike is.
    private func amplitude(atSample index: Int) -> Float {
        let span = Int(config.amplitudeMeasureSeconds * config.sampleRate)
        var scratch = [Float]()
        guard ring.read(from: index, count: span, into: &scratch) else { return 0 }
        var peak: Float = 0
        for value in scratch { peak = max(peak, abs(value)) }
        return peak
    }

    private func emit(_ onset: OnsetDetector.Onset, fingerprinter: Fingerprinter) {
        let hostTime = hostSeconds(forSample: onset.sampleIndex)
        let peak = amplitude(atSample: onset.sampleIndex)

        // Too quiet to be a mallet strike. Silent by design — this fires on room
        // noise many times a second and is not something to report (except to the
        // audio test screen, which wants to see the noise floor vs the gate).
        let gate = max(config.minStrikeAmplitude,
                       config.minAmplitudeRelative * strikeAmplitudePeak)
        guard peak >= gate else {
            reportOnsetDebug(hostTime: hostTime, amplitude: peak, gate: gate, passedGate: false, fingerprinted: false)
            return
        }
        strikeAmplitudePeak = max(strikeAmplitudePeak * amplitudePeakDecay, peak)

        // Record the onset time so the vision path can snap its (frame-grained)
        // strike timing onto this (sub-ms) onset when the two line up.
        recordOnset(hostTime)

        // The strike trigger. Detection identifies the key from vision now, so
        // this is all a normal strike needs — no per-key audio classification.
        DispatchQueue.main.async { [weak self] in self?.onStrikeDetected?(hostTime) }

        // The fingerprint is only needed for calibration (capture / live feed) and
        // the audio test's quality readout. Skip the 4096-pt FFT entirely in normal
        // play — nothing consumes it there anymore.
        guard capture != nil || onCalibrationStrike != nil || onOnsetDebug != nil else { return }

        guard let vector = fingerprinter.fingerprint(onsetSample: onset.sampleIndex, ring: ring) else {
            reportOnsetDebug(hostTime: hostTime, amplitude: peak, gate: gate, passedGate: true, fingerprinted: false)
            return
        }
        reportOnsetDebug(hostTime: hostTime, amplitude: peak, gate: gate, passedGate: true, fingerprinted: true)

        // A capture window collects candidates rather than reporting the first.
        if capture != nil {
            let hz = fingerprinter.estimateFundamental(onsetSample: onset.sampleIndex, ring: ring)
            let partials = fingerprinter.topPeaks(onsetSample: onset.sampleIndex, ring: ring, count: 4)
            let strike = CapturedStrike(fingerprint: vector,
                                        fundamentalHz: hz,
                                        hostTime: hostTime,
                                        amplitude: peak,
                                        topPartials: partials)
            capture?.candidateCount += 1
            if strike.amplitude > (capture?.best?.amplitude ?? -1) {
                capture?.best = strike
            }
            return
        }

        if onCalibrationStrike != nil {
            let hz = fingerprinter.estimateFundamental(onsetSample: onset.sampleIndex, ring: ring)
            DispatchQueue.main.async { [weak self] in
                self?.onCalibrationStrike?(vector, hz, hostTime)
            }
        }
    }

    /// Absolute sample index → CACurrentMediaTime seconds.
    private func hostSeconds(forSample index: Int) -> Double {
        guard let anchor = anchorHostSeconds else { return CACurrentMediaTime() }
        return anchor + Double(index - anchorSampleIndex) / config.sampleRate
    }

    // MARK: - Onset timing (for the vision path)

    // MARK: - Live gate tuning (audio test screen)

    /// The current amplitude-gate settings, read on the DSP queue so it never
    /// races with `emit`. Lets the audio test screen seed its sliders.
    func gateSettings() -> (floor: Float, relative: Float) {
        queue.sync { (config.minStrikeAmplitude, config.minAmplitudeRelative) }
    }

    /// Adjust the amplitude gate live. Applied on the DSP queue, so it takes
    /// effect on the next onset without a restart.
    func setGate(floor: Float, relative: Float) {
        queue.async { [weak self] in
            self?.config.minStrikeAmplitude = floor
            self?.config.minAmplitudeRelative = relative
        }
    }

    private func reportOnsetDebug(hostTime: Double, amplitude: Float, gate: Float,
                                  passedGate: Bool, fingerprinted: Bool) {
        guard onOnsetDebug != nil else { return }
        let debug = OnsetDebug(hostTime: hostTime, amplitude: amplitude, gate: gate,
                               passedGate: passedGate, fingerprinted: fingerprinted)
        DispatchQueue.main.async { [weak self] in self?.onOnsetDebug?(debug) }
    }

    private func recordOnset(_ hostTime: Double) {
        recentOnsetsLock.lock()
        defer { recentOnsetsLock.unlock() }
        recentOnsets.append(hostTime)
        // Keep only the last ~2s; older onsets can't match a current strike.
        let cutoff = hostTime - 2.0
        if recentOnsets.first ?? .greatestFiniteMagnitude < cutoff {
            recentOnsets.removeAll { $0 < cutoff }
        }
    }

    /// The onset time closest to `hostTime` within `tolerance` seconds, or nil.
    /// The vision path uses this to sharpen its strike timing without ever
    /// depending on it — nil just means "keep the visual time".
    func nearestOnset(to hostTime: Double, within tolerance: Double) -> Double? {
        recentOnsetsLock.lock()
        defer { recentOnsetsLock.unlock() }
        return recentOnsets
            .filter { abs($0 - hostTime) <= tolerance }
            .min { abs($0 - hostTime) < abs($1 - hostTime) }
    }
}

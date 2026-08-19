//
//  AudioEngineController.swift
//  Kotek
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
        /// Cosine similarity to the generic gangsa-strike baseline, if one is set.
        /// High for a real strike, low for a scream/clap — nil when no baseline.
        let baselineSimilarity: Double?
    }
    var onOnsetDebug: ((OnsetDebug) -> Void)?

    /// Called on the main queue when a strike is confirmed as a real gangsa hit:
    /// it passed the amplitude gate AND its spectrum matched the learned baseline
    /// above `baselineThreshold`. This is the play trigger when a baseline exists —
    /// vision then decides which key at `hostTime`. Blocks hovers (no sound) and
    /// screams (wrong spectrum). Never fires when no baseline is set.
    var onConfirmedStrike: ((_ hostTime: Double) -> Void)?

    /// Called on the main queue for every onset, with the fingerprint that the
    /// calibration flow should store, plus a display-only pitch estimate.
    var onCalibrationStrike: ((_ fingerprint: [Float], _ fundamentalHz: Double, _ hostTime: Double) -> Void)?

    /// Progress while learning the strike-sound baseline. `accepted` is how many
    /// consistent strikes are in the template so far; `wasAccepted` says whether
    /// the strike that just triggered this was folded in or rejected as an
    /// outlier (e.g. a scream); `similarity` is that strike's cosine to the
    /// running average (nil while still seeding).
    struct BaselineProgress {
        let accepted: Int
        let wasAccepted: Bool
        let similarity: Double?
    }
    var onBaselineProgress: ((BaselineProgress) -> Void)?

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
    private let queue = DispatchQueue(label: "me.babono.kotek.audio.dsp")

    private var config = DSPConfig()
    private var ring = SampleRing(capacity: 1)
    private var onsetFFT: FFTProcessor?
    private var fingerprintFFT: FFTProcessor?
    private var flux: SpectralFlux?
    private var detector: OnsetDetector?
    private var fingerprinter: Fingerprinter?
    private var classifier: KeyClassifier?

    /// The polyphonic second opinion. Lives on the DSP queue; every strike is
    /// decomposed there and the result cached by host time, so the play loop's
    /// lookups never run NNLS on the main actor.
    private var decomposer: KeyDecomposer?
    /// One decomposed strike, kept long enough for the play loop to ask about it.
    struct StrikeOpinion {
        let hostTime: Double
        /// nil until the dictionary has enough learned keys to be usable.
        let decomposition: Decomposition?
        /// The linear band vector, so a key the CAMERA identifies can be folded
        /// into the dictionary after the fact.
        let bands: [Float]
    }
    private var recentOpinions: [StrikeOpinion] = []
    private let opinionsLock = NSLock()
    /// DSP-queue only — see `setKeyOpinionsEnabled`.
    private var keyOpinionsEnabled = false

    /// Generic "this is a gangsa strike" spectral template (L2-normalised), used
    /// to tell a real strike from a scream/clap. `baselineAccumulator` collects
    /// fingerprints while learning it. Both live on the DSP queue.
    private var strikeBaseline: [Float]?
    private var baselineAccumulator: [[Float]]?
    /// Similarity a strike must reach to be confirmed gangsa. Tuned in the audio
    /// test screen. Accessed on the DSP queue.
    private var baselineThreshold: Float = 0.5
    /// While LEARNING the baseline: how many strikes to take on trust to seed the
    /// template, and how similar a later strike must be to the running average to
    /// be folded in rather than rejected as an outlier (a scream, a clap). This
    /// is what stops non-gangsa sounds from raising the confidence.
    private let baselineSeedCount = 2
    private let baselineLearnConsistency: Float = 0.55
    /// Collapse the several onsets one physical strike can produce.
    private var lastBaselineOnsetTime: Double = 0

    /// Live gate overrides from the audio test screen. Kept separate from `config`
    /// so they survive `start()` reconfiguring, which replaces `config` wholesale.
    private var gateFloorOverride: Float?
    private var gateRelativeOverride: Float?

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
        // Re-apply any live gate tuning the audio test screen set this session.
        if let f = gateFloorOverride { config.minStrikeAmplitude = f }
        if let r = gateRelativeOverride { config.minAmplitudeRelative = r }

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

        let decomposer = KeyDecomposer(bandCount: config.fpBands)
        var templates: [Int: [Float]] = [:]
        for key in keys {
            if let template = key.linearTemplate, template.count == config.fpBands {
                templates[key.index] = template
            }
        }
        decomposer.load(templates: templates)
        self.decomposer = decomposer
        setOpinions([])

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
            reportOnsetDebug(hostTime: hostTime, amplitude: peak, gate: gate, passedGate: false, fingerprinted: false, baselineSimilarity: nil)
            return
        }
        strikeAmplitudePeak = max(strikeAmplitudePeak * amplitudePeakDecay, peak)

        // Record the onset time so the vision path can snap its (frame-grained)
        // strike timing onto this (sub-ms) onset when the two line up.
        recordOnset(hostTime)

        // The strike trigger. Detection identifies the key from vision now, so
        // this is all a normal strike needs — no per-key audio classification.
        DispatchQueue.main.async { [weak self] in self?.onStrikeDetected?(hostTime) }

        // The second opinion. Costs one extra 4096-point FFT per strike — tens
        // of microseconds, at most twenty strikes a second — plus an NNLS solve
        // that is 12x12 once the Gram matrix is built. Deliberately done here on
        // the DSP queue rather than lazily on lookup, both to keep the work off
        // the main actor and because `previous` only means anything if strikes
        // are decomposed in the order they were played.
        if keyOpinionsEnabled, let bands = fingerprinter.linearBands(onsetSample: onset.sampleIndex, ring: ring) {
            let decomposition = decomposer?.decompose(linearBands: bands)
            recordOpinion(StrikeOpinion(hostTime: hostTime,
                                        decomposition: decomposition,
                                        bands: bands))
        }

        // The fingerprint is needed for calibration, the audio test's readout, and
        // the gangsa-strike baseline (learning it or scoring against it). Skip the
        // 4096-pt FFT entirely in normal play when none of those are active.
        guard capture != nil || onCalibrationStrike != nil || onOnsetDebug != nil
                || baselineAccumulator != nil || strikeBaseline != nil else { return }

        guard let vector = fingerprinter.fingerprint(onsetSample: onset.sampleIndex, ring: ring) else {
            reportOnsetDebug(hostTime: hostTime, amplitude: peak, gate: gate, passedGate: true, fingerprinted: false, baselineSimilarity: nil)
            return
        }

        // While LEARNING the baseline, fold in strikes that resemble the ones
        // already collected and reject outliers, so a scream can't build (or
        // poison) the template. The first `baselineSeedCount` are taken on trust
        // to seed it — strike the gangsa, not yourself, at the start.
        if var acc = baselineAccumulator {
            // Collapse the multiple onsets one strike can fire.
            if hostTime - lastBaselineOnsetTime >= 0.2 {
                lastBaselineOnsetTime = hostTime
                var wasAccepted = true
                var sim: Double?
                if acc.count >= baselineSeedCount, let avg = KeyClassifier.averageFingerprints(acc) {
                    let s = dot(avg, vector)
                    sim = Double(s)
                    wasAccepted = s >= baselineLearnConsistency
                }
                if wasAccepted { acc.append(vector); baselineAccumulator = acc }
                let acceptedCount = acc.count
                DispatchQueue.main.async { [weak self] in
                    self?.onBaselineProgress?(BaselineProgress(accepted: acceptedCount,
                                                               wasAccepted: wasAccepted,
                                                               similarity: sim))
                }
            }
        }
        let similarity = strikeBaseline.map { Double(dot($0, vector)) }
        reportOnsetDebug(hostTime: hostTime, amplitude: peak, gate: gate, passedGate: true, fingerprinted: true, baselineSimilarity: similarity)

        // Confirmed gangsa strike → the play trigger.
        if let similarity, similarity >= Double(baselineThreshold) {
            DispatchQueue.main.async { [weak self] in self?.onConfirmedStrike?(hostTime) }
        }

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
            self?.gateFloorOverride = floor
            self?.gateRelativeOverride = relative
            self?.config.minStrikeAmplitude = floor
            self?.config.minAmplitudeRelative = relative
        }
    }

    private func reportOnsetDebug(hostTime: Double, amplitude: Float, gate: Float,
                                  passedGate: Bool, fingerprinted: Bool,
                                  baselineSimilarity: Double?) {
        guard onOnsetDebug != nil else { return }
        let debug = OnsetDebug(hostTime: hostTime, amplitude: amplitude, gate: gate,
                               passedGate: passedGate, fingerprinted: fingerprinted,
                               baselineSimilarity: baselineSimilarity)
        DispatchQueue.main.async { [weak self] in self?.onOnsetDebug?(debug) }
    }

    // MARK: - Polyphonic key opinion

    /// Whether to decompose each strike. Off by default so nothing outside the
    /// play loop pays for it. Applied on the DSP queue, which is the only place
    /// it is read.
    func setKeyOpinionsEnabled(_ enabled: Bool) {
        queue.async { [weak self] in
            self?.keyOpinionsEnabled = enabled
        }
    }

    /// Restrict the dictionary to the bilah this figure uses, mirroring what
    /// `StrikeFusion.setActiveKeys` does for vision.
    ///
    /// A kotekan touches three or four keys. Leaving the other six in the
    /// dictionary gives the fit six extra ways to explain a spectrum it should
    /// be attributing to one of the four — and unlike vision, where an unused
    /// key simply is not looked at, an unused ATOM actively competes.
    func setDecompositionKeys(_ indices: Set<Int>) {
        queue.async { [weak self] in self?.decomposer?.restrict(to: indices) }
    }

    /// The audio opinion for the strike nearest `hostTime`, if one was recorded
    /// within `tolerance`. Returns nil when the dictionary is not yet usable, the
    /// residual was too high to trust, or no key cleared the share floor.
    ///
    /// This is a RECOVERY path, called only when vision declined to name a key.
    /// It is never consulted to second-guess a confident visual decision.
    func keyOpinion(at hostTime: Double, within tolerance: Double = 0.12) -> KeyActivation? {
        opinionsLock.lock()
        let match = recentOpinions
            .filter { abs($0.hostTime - hostTime) <= tolerance }
            .min { abs($0.hostTime - hostTime) < abs($1.hostTime - hostTime) }
        opinionsLock.unlock()

        // `isTrusted` was decided on the DSP queue when the strike was decomposed,
        // so nothing owned by that queue is read from here.
        guard let decomposition = match?.decomposition,
              decomposition.isTrusted,
              let best = decomposition.best else { return nil }
        return best
    }

    /// The full decomposition nearest `hostTime`, trusted or not.
    ///
    /// `keyOpinion` deliberately withholds anything the residual bar has not
    /// cleared, which is right for play and useless for debugging — the whole
    /// point of the test screen is to watch the ear while it is still learning.
    func debugOpinion(at hostTime: Double, within tolerance: Double = 0.12) -> Decomposition? {
        opinionsLock.lock()
        defer { opinionsLock.unlock() }
        return recentOpinions
            .filter { abs($0.hostTime - hostTime) <= tolerance }
            .min { abs($0.hostTime - hostTime) < abs($1.hostTime - hostTime) }?
            .decomposition
    }

    /// Teach the dictionary: the camera identified `keyIndex` at `hostTime`.
    ///
    /// This is the whole calibration story. There is no strike-each-key-in-turn
    /// step; the eye labels the training data for the ear, every session, on the
    /// instrument actually in front of the player.
    func learnKey(_ keyIndex: Int, at hostTime: Double, within tolerance: Double = 0.12) {
        opinionsLock.lock()
        let match = recentOpinions
            .filter { abs($0.hostTime - hostTime) <= tolerance }
            .min { abs($0.hostTime - hostTime) < abs($1.hostTime - hostTime) }
        opinionsLock.unlock()

        guard let opinion = match else { return }
        let residual = opinion.decomposition?.residual
        queue.async { [weak self] in
            self?.decomposer?.learn(keyIndex: keyIndex, linearBands: opinion.bands)
            // This strike is known-real and known-correct, so its residual is a
            // sample of what "normal" looks like on this instrument in this room.
            if let residual { self?.decomposer?.noteConfirmedResidual(residual) }
        }
    }

    /// Record what the camera decided, so the eye/ear agreement rate accumulates
    /// even while audio has no vote. Cheap, and the only thing that could ever
    /// justify giving it one.
    func noteVisionDecision(_ keyIndex: Int, confidence: Double, at hostTime: Double,
                            within tolerance: Double = 0.12) {
        opinionsLock.lock()
        let match = recentOpinions
            .filter { abs($0.hostTime - hostTime) <= tolerance }
            .min { abs($0.hostTime - hostTime) < abs($1.hostTime - hostTime) }
        opinionsLock.unlock()

        let decomposition = match?.decomposition
        queue.async { [weak self] in
            self?.decomposer?.noteVisionDecision(keyIndex: keyIndex,
                                                 confidence: confidence,
                                                 against: decomposition)
        }
    }

    /// Note that audio supplied a key vision could not.
    func noteRecovery() {
        queue.async { [weak self] in self?.decomposer?.noteRecovery() }
    }

    /// Eye/ear agreement so far this session, for the diagnostics screen.
    func agreementStats(completion: @escaping (KeyDecomposer.Agreement) -> Void) {
        queue.async { [weak self] in
            let stats = self?.decomposer?.agreement ?? KeyDecomposer.Agreement()
            DispatchQueue.main.async { completion(stats) }
        }
    }

    /// Learned atoms, to fold back into the profile at the end of a session.
    func learnedTemplates(completion: @escaping ([Int: [Float]]) -> Void) {
        queue.async { [weak self] in
            let templates = self?.decomposer?.templates() ?? [:]
            DispatchQueue.main.async { completion(templates) }
        }
    }

    /// How many examples each key has collected, for the diagnostics screen.
    func decompositionProgress(completion: @escaping ([Int: Int]) -> Void) {
        queue.async { [weak self] in
            let progress = self?.decomposer?.progress() ?? [:]
            DispatchQueue.main.async { completion(progress) }
        }
    }

    private func recordOpinion(_ opinion: StrikeOpinion) {
        opinionsLock.lock()
        defer { opinionsLock.unlock() }
        recentOpinions.append(opinion)
        let cutoff = opinion.hostTime - 2.0
        if recentOpinions.first.map({ $0.hostTime < cutoff }) == true {
            recentOpinions.removeAll { $0.hostTime < cutoff }
        }
    }

    private func setOpinions(_ opinions: [StrikeOpinion]) {
        opinionsLock.lock()
        recentOpinions = opinions
        opinionsLock.unlock()
    }

    // MARK: - Gangsa-strike baseline

    /// Whether a generic strike baseline has been learned this session.
    var hasStrikeBaseline: Bool { queue.sync { strikeBaseline != nil } }

    /// Begin averaging the next strikes into a generic gangsa-strike template.
    func startBaselineCapture() {
        queue.async { [weak self] in
            self?.baselineAccumulator = []
            self?.lastBaselineOnsetTime = 0
        }
    }

    /// Get the current generic gangsa-strike spectral baseline template.
    func getBaselineTemplate() -> [Float]? {
        queue.sync { strikeBaseline }
    }

    /// Load a persisted generic gangsa-strike spectral baseline template.
    func setBaselineTemplate(_ template: [Float]?) {
        queue.async { [weak self] in
            self?.strikeBaseline = template
        }
    }

    /// Finish learning; averages the collected fingerprints into the baseline.
    /// Returns the number of strikes that went into it (0 = nothing captured).
    func finishBaselineCapture(completion: @escaping (Int, [Float]?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let collected = self.baselineAccumulator ?? []
            self.baselineAccumulator = nil
            let template = KeyClassifier.averageFingerprints(collected)
            if let template {
                self.strikeBaseline = template
            }
            DispatchQueue.main.async { completion(collected.count, template) }
        }
    }

    func clearBaseline() {
        queue.async { [weak self] in
            self?.strikeBaseline = nil
            self?.baselineAccumulator = nil
        }
    }

    /// The similarity threshold a strike must clear to be confirmed gangsa.
    func setBaselineThreshold(_ value: Float) {
        queue.async { [weak self] in self?.baselineThreshold = value }
    }

    /// Cosine similarity of two L2-normalised fingerprints.
    private func dot(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var sum: Float = 0
        for i in 0..<a.count { sum += a[i] * b[i] }
        return sum
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

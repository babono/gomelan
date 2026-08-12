//
//  OnsetDetector.swift
//  gomelan
//
//  Port of `find_onsets` + `refine_onset` in gamelan_dsp.py.
//
//  A funnel, in the same order as the Python:
//
//    flux  ->  adaptive median threshold  ->  local maxima  ->  minimum spacing
//          ->  sample-accurate refinement ->  spacing enforced AGAIN
//
//  Streaming changes one thing only: Python evaluates a whole clip at once, so
//  it can look forward freely. Here every stage is delayed by `lookaheadFrames`
//  (half the median window) so the same centred median and the same 3-frame peak
//  test are available. That delay is ~100ms and is already being paid for by the
//  fingerprint window, so it costs nothing extra.
//
//  Four traps live in here. All four cost real debugging time in Python and all
//  four are just as easy to reintroduce in Swift:
//
//   1. Frame times are the window CENTRE, not its start. Using the start puts
//      every onset ~12ms early — a constant bias that silently corrupts timing.
//   2. Minimum spacing must be enforced AFTER refinement as well as before.
//      Refinement can pull two candidates onto the same attack.
//   3. Refinement tracks the envelope's RISE, not its level. An amplitude
//      threshold latches onto the previous note still ringing.
//   4. (In the scorer, not here) score by grid slot, never by list position.
//

import Foundation

final class OnsetDetector {

    /// Absolute sample index of a detected attack.
    struct Onset {
        let sampleIndex: Int
        /// Flux strength that produced it, for diagnostics.
        let strength: Float
    }

    private let config: DSPConfig

    // Flux history, indexed by frame, with `historyOffset` as the absolute frame
    // number of element 0. Trimmed so it never grows without bound.
    private var flux: [Float] = []
    private var historyOffset = 0
    private var nextFrameToEvaluate = 0

    // Best candidate not yet committed, held open until it is clear no stronger
    // one arrives within minGap. This is the streaming form of the Python's
    // "sort candidates strongest-first, then greedily enforce spacing" — a weak
    // early blip must not be able to claim the slot and block the real strike.
    private var pendingFrame: Int?
    private var pendingStrength: Float = 0

    /// nil until the first onset is emitted. Deliberately not `Int.min` — the
    /// spacing check subtracts from it, which would overflow.
    private var lastEmittedSample: Int?

    /// Supplies raw samples for refinement. Set by the owner.
    var sampleProvider: ((_ from: Int, _ count: Int, _ into: inout [Float]) -> Bool)?

    private var refineScratch: [Float] = []
    private var envelope: [Float] = []

    init(config: DSPConfig) {
        self.config = config
    }

    func reset() {
        flux.removeAll(keepingCapacity: true)
        historyOffset = 0
        nextFrameToEvaluate = 0
        pendingFrame = nil
        pendingStrength = 0
        lastEmittedSample = nil
    }

    private var lookaheadFrames: Int { config.medianLengthFrames / 2 }

    /// Absolute sample index at the CENTRE of a frame's analysis window.
    /// Trap 1 lives here — do not change this to `frame * hop`.
    private func centreSample(ofFrame frame: Int) -> Int {
        frame * config.onsetHop + config.onsetWindow / 2
    }

    /// Feed one flux value, already normalised into Python's 0...1 range.
    /// Returns any onsets that became final as a result.
    func append(flux value: Float) -> [Onset] {
        flux.append(value)
        var emitted: [Onset] = []

        // A frame can only be judged once its whole median window exists.
        while nextFrameToEvaluate + lookaheadFrames < historyOffset + flux.count {
            if let onset = evaluate(frame: nextFrameToEvaluate) {
                emitted.append(onset)
            }
            nextFrameToEvaluate += 1
        }

        trimHistory()
        return emitted
    }

    private func evaluate(frame: Int) -> Onset? {
        let half = lookaheadFrames
        guard let value = self[frame] else { return nil }

        // --- adaptive threshold: median of the local neighbourhood * 1.6 ---
        // "You must be 60% above what is normal around here." During a loud busy
        // passage the local median rises and the bar rises with it; in a quiet
        // stretch it drops and soft hits still count.
        var neighbourhood: [Float] = []
        neighbourhood.reserveCapacity(2 * half + 1)
        for f in (frame - half)...(frame + half) {
            // mode="nearest": clamp at the edges rather than assuming silence.
            neighbourhood.append(self[clampFrame(f)] ?? value)
        }
        neighbourhood.sort()
        let median = neighbourhood[neighbourhood.count / 2]
        let threshold = max(median * config.threshMultiplier, config.threshFloor)

        // --- local maximum over 3 frames ---
        // Flux stays high for several frames per strike; without this you would
        // get one onset per frame instead of one per strike. `>=` not `>` so a
        // flat top still registers — the spacing stage removes the duplicate.
        let previous = self[clampFrame(frame - 1)] ?? value
        let next = self[clampFrame(frame + 1)] ?? value
        let isPeak = value >= max(previous, next)

        guard isPeak, value > threshold else { return nil }
        return promote(frame: frame, strength: value)
    }

    /// Minimum-spacing rule, strongest-first.
    private func promote(frame: Int, strength: Float) -> Onset? {
        guard let held = pendingFrame else {
            pendingFrame = frame
            pendingStrength = strength
            return nil
        }

        if frame - held < config.minGapFrames {
            // Too close to decide between them — keep only the louder.
            if strength > pendingStrength {
                pendingFrame = frame
                pendingStrength = strength
            }
            return nil
        }

        let committed = commit(frame: held)
        pendingFrame = frame
        pendingStrength = strength
        return committed
    }

    /// Flush a candidate that has been held longer than minGap can still affect.
    /// Called when the stream ends or the detector is drained.
    func flush() -> [Onset] {
        guard let held = pendingFrame else { return [] }
        pendingFrame = nil
        if let onset = commit(frame: held) { return [onset] }
        return []
    }

    private func commit(frame: Int) -> Onset? {
        let coarse = centreSample(ofFrame: frame)
        let refined = refine(coarseSample: coarse)

        // Trap 2: refinement can pull two neighbouring candidates onto the SAME
        // attack, so the spacing rule has to be applied again afterwards.
        // Enforcing it only on the coarse frames leaves duplicates ~1ms apart.
        let minGapSamples = Int(config.minGapSeconds * config.sampleRate)
        if let last = lastEmittedSample, refined - last < minGapSamples { return nil }

        lastEmittedSample = refined
        return Onset(sampleIndex: refined, strength: self[frame] ?? 0)
    }

    // MARK: - Refinement

    /// Snap a coarse STFT onset to the sample where the attack actually begins.
    /// STFT gives ~6ms resolution at best; timing feedback is measured in
    /// milliseconds, so this is worth the few lines it costs.
    private func refine(coarseSample: Int, searchSeconds: Double = 0.030,
                        riseFraction: Float = 0.15) -> Int {
        let span = Int(searchSeconds * config.sampleRate)
        let lo = max(0, coarseSample - span)
        let hi = coarseSample + span
        let count = hi - lo
        guard count >= 64, let provider = sampleProvider,
              provider(lo, count, &refineScratch) else { return coarseSample }

        for i in 0..<count { refineScratch[i] = abs(refineScratch[i]) }

        // Moving-average envelope, k=32, matching the Python's np.convolve(mode="same").
        let k = 32
        if envelope.count != count { envelope = [Float](repeating: 0, count: count) }
        var running: Float = 0
        let halfK = k / 2
        for i in 0..<count {
            running += refineScratch[i]
            if i >= k { running -= refineScratch[i - k] }
            let centre = i - halfK
            if centre >= 0 { envelope[centre] = running / Float(k) }
        }
        for i in max(0, count - halfK)..<count { envelope[i] = envelope[max(0, count - halfK - 1)] }

        var peak: Float = 0
        for v in envelope where v > peak { peak = v }
        guard peak > 1e-6 else { return coarseSample }

        // Trap 3: track the RISE, not the level. A previous note still ringing
        // sits high but is FALLING, so slope ignores it where an amplitude
        // threshold would snap onto it and report the hit ~35ms early.
        var steepest = 0
        var steepestSlope: Float = 0
        for i in 0..<(count - 1) {
            let slope = envelope[i + 1] - envelope[i]
            if slope > steepestSlope { steepestSlope = slope; steepest = i }
        }
        guard steepestSlope > 0 else { return coarseSample }

        // Walk back to where the rise began.
        let cutoff = riseFraction * steepestSlope
        var i = steepest
        while i > 0, envelope[i] - envelope[i - 1] > cutoff { i -= 1 }

        return lo + i
    }

    // MARK: - History helpers

    private subscript(frame: Int) -> Float? {
        let idx = frame - historyOffset
        guard idx >= 0, idx < flux.count else { return nil }
        return flux[idx]
    }

    private func clampFrame(_ frame: Int) -> Int {
        min(max(frame, historyOffset), historyOffset + flux.count - 1)
    }

    private func trimHistory() {
        // Keep a comfortable margin behind the evaluation point.
        let keepFrom = nextFrameToEvaluate - config.medianLengthFrames * 2
        guard keepFrom > historyOffset else { return }
        let drop = keepFrom - historyOffset
        flux.removeFirst(drop)
        historyOffset = keepFrom
    }
}

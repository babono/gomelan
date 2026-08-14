//
//  StrikeFusion.swift
//  gomelan
//
//  Scores camera frames against the per-key hit classifier and reconciles them
//  with the calibrated key layout. Detection strategy lives in the caller:
//
//  - VISION-FIRST / self-triggering (primary): the play loop polls `latestScores`
//    continuously and feeds a VisionStrikeDetector (rising edge). No audio onset
//    is involved, so it's immune to background noise.
//  - Audio-triggered helpers (`resolveVisionFirst`, `resolve(candidates:)`) score
//    the frame at a given strike time; kept for the audio-master fallback.
//
//  All paths share `decide()`. Vision answers *which key by location* (we choose
//  the crops), never by pitch identity.
//
//  This is an ACTOR on purpose. Classifying one crop is a CoreML inference, and
//  the play loop asks for every key several times a second; run on the main
//  actor (which is this target's default isolation) that work sat on the same
//  thread as the display link and SwiftUI, and the whole session stuttered.
//  Being an actor puts every inference on the cooperative pool instead.
//

import CoreGraphics
import QuartzCore

actor StrikeFusion {

    struct Decision {
        let keyIndex: Int
        let hitProbability: Double
    }

    private let frames: FrameBuffer
    private let classifier: MalletHitClassifier?
    private let keys: [InstrumentKey]

    /// The overlay's coordinate space, updated as the view lays out — this is
    /// what the aspect-fill crop maps back through onto the frame.
    private var viewSize: CGSize

    /// Which keys are worth classifying. A kotekan touches three or four bilah;
    /// scoring all ten was most of the vision cost for nothing. Empty = all.
    private var activeKeys: Set<Int> = []

    /// A crop must score at least this to count as a strike. Tune on device.
    private var minHitProbability = 0.45

    /// The frame `latestScores` last classified. The play loop polls faster than
    /// the camera delivers, so without this the same frame is scored twice.
    private var lastScoredHostTime: Double = -1

    init(frames: FrameBuffer, keys: [InstrumentKey], viewSize: CGSize) {
        self.frames = frames
        self.classifier = MalletHitClassifier()
        self.keys = keys
        self.viewSize = viewSize
    }

    func setViewSize(_ size: CGSize) { viewSize = size }

    /// Restrict scoring to the bilah this figure actually uses.
    func setActiveKeys(_ indices: Set<Int>) { activeKeys = indices }

    func setMinHitProbability(_ value: Double) { minHitProbability = value }

    /// Hit probability for every key in the most recent buffered frame, tagged
    /// with that frame's host time. Drives the self-triggering play loop. Returns
    /// nil until vision + a laid-out view + a frame are all available, or when
    /// the newest frame has already been scored.
    func latestScores() -> (scores: [Int: Double], hostTime: Double)? {
        guard viewSize.width > 0, viewSize.height > 0,
              let frame = frames.nearest(to: CACurrentMediaTime()),
              frame.hostTime != lastScoredHostTime else { return nil }
        lastScoredHostTime = frame.hostTime
        return (scores(in: frame), frame.hostTime)
    }

    /// Vision-first resolution: on an audio-triggered strike, classify EVERY key
    /// at the frame nearest `hostTime` and return the one most clearly being hit
    /// (argmax over the threshold). Audio contributes only the trigger + timing.
    /// Returns nil when vision is unavailable, the view isn't laid out, no frame
    /// is buffered, or no key clears the threshold.
    func resolveVisionFirst(hostTime: Double) -> Decision? {
        guard viewSize.width > 0, viewSize.height > 0,
              let frame = frames.nearest(to: hostTime) else { return nil }
        return Self.decide(visionScores: scores(in: frame), threshold: minHitProbability)
    }

    /// Classify the keys in play in a single frame.
    private func scores(in frame: FrameBuffer.Frame) -> [Int: Double] {
        guard let classifier else { return [:] }
        var scores: [Int: Double] = [:]
        for key in keys where activeKeys.isEmpty || activeKeys.contains(key.index) {
            let cropRect = CropMapper.bufferRect(overlay: key.rect,
                                                 bufferSize: frame.size,
                                                 viewSize: viewSize)
            scores[key.index] = classifier.hitProbability(in: frame.image, cropRect: cropRect)
        }
        return scores
    }

    /// Try to resolve an unclear audio strike using vision. Returns nil when
    /// vision is unavailable, no frame is buffered, the view isn't laid out yet,
    /// or no crop clears the threshold. Runs inline: it only fires on the rare
    /// unclear strike, and the model is small enough not to stall a frame.
    func resolve(candidates: [(keyIndex: Int, similarity: Double)],
                 hostTime: Double) -> Decision? {
        guard let classifier,
              !candidates.isEmpty,
              viewSize.width > 0, viewSize.height > 0,
              let frame = frames.nearest(to: hostTime) else { return nil }

        var scores: [Int: Double] = [:]
        for candidate in candidates {
            guard let key = keys.first(where: { $0.index == candidate.keyIndex }) else { continue }
            let cropRect = CropMapper.bufferRect(overlay: key.rect,
                                                 bufferSize: frame.size,
                                                 viewSize: viewSize)
            scores[candidate.keyIndex] = classifier.hitProbability(in: frame.image, cropRect: cropRect)
        }
        return Self.decide(visionScores: scores, threshold: minHitProbability)
    }

    /// Pure decision core: pick the highest-scoring candidate that clears the
    /// threshold. Separated out so the fusion policy is unit-testable without a
    /// camera or a model.
    static func decide(visionScores: [Int: Double], threshold: Double) -> Decision? {
        guard let best = visionScores.max(by: { $0.value < $1.value }),
              best.value >= threshold else { return nil }
        return Decision(keyIndex: best.key, hitProbability: best.value)
    }
}

//
//  StrikeFusion.swift
//  gomelan
//
//  Combines the audio and vision detectors. Audio stays the master: it owns
//  timing, and any strike it can identify confidently flows straight through.
//  Vision is only asked to help when audio reports an UNCLEAR strike — it heard a
//  hit but two key templates were too close to call (see KeyClassifier.classify).
//
//  In that case we take the frame nearest the strike's hostTime, crop each of
//  audio's top candidate keys, and let MalletHitClassifier say which region is
//  actually being struck. If vision can't tell either, we keep today's behaviour
//  and report nothing rather than guess.
//

import CoreGraphics

final class StrikeFusion {

    struct Decision {
        let keyIndex: Int
        let hitProbability: Double
    }

    private let frames: FrameBuffer
    private let classifier: MalletHitClassifier?
    private let keys: [InstrumentKey]

    /// The overlay's coordinate space, updated as the view lays out — this is
    /// what the aspect-fill crop maps back through onto the frame.
    var viewSize: CGSize

    /// A crop must score at least this to count as a strike. Tune on device.
    var minHitProbability = 0.5

    init(frames: FrameBuffer, keys: [InstrumentKey], viewSize: CGSize) {
        self.frames = frames
        self.classifier = MalletHitClassifier()
        self.keys = keys
        self.viewSize = viewSize
    }

    /// Try to resolve an unclear audio strike using vision. Returns nil when
    /// vision is unavailable, no frame is buffered, the view isn't laid out yet,
    /// or no crop clears the threshold. Runs inline: it only fires on the rare
    /// unclear strike, and the model is small enough not to stall a frame.
    func resolve(candidates: [(keyIndex: Int, similarity: Double)],
                 hostTime: Double) async -> Decision? {
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

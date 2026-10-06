//
//  MalletHitClassifier.swift
//  Kotek
//
//  Wraps MalletDetector.mlmodel (a Vision image classifier, labels hit/not-hit).
//  The model was trained on CROPPED key images, so at inference it must be fed a
//  crop of a single key region — never the whole frame. Feeding it the same kind
//  of crop it trained on is what keeps this small feature-print model reliable.
//
//  This is a strike detector, not a key identifier: it answers "is this region
//  being struck?", and we choose which region to run it on. Which key it belongs
//  to comes from WHERE we cropped, not from the model.
//

import Vision
import CoreML
import CoreGraphics

/// Nonisolated so StrikeFusion can run inference off the main actor — this
/// target defaults to MainActor isolation, which would otherwise put every
/// CoreML call on the same thread as the display link.
nonisolated final class MalletHitClassifier {

    private let model: VNCoreMLModel

    /// How Vision fits the (non-square) key crop into the model's square input.
    ///
    /// MEASURED, not assumed. This was `.scaleFill` on the strength of a comment
    /// claiming it matched Create ML, which nobody had verified — and it was
    /// wrong. After retraining, every key scored 0.00 on every frame while
    /// Create ML reported 92%: the model was being shown a different picture at
    /// inference than it learned from, and silently returning nothing. Switching
    /// to `.centerCrop` on device fixed it immediately.
    ///
    /// The two are not close on these crops. Key 0 is 58x294 — a 1:5 sliver.
    /// `.scaleFill` stretches the whole bar into the square; `.centerCrop` scales
    /// the short side to fit and keeps a square from the middle, so the model
    /// sees roughly the central fifth of the bar at full width. That happens to
    /// be where a mallet lands, which is presumably why it works well.
    ///
    /// The consequence worth remembering: THE MODEL NEVER SEES THE ENDS OF A BAR.
    /// If strikes near a bar's extremities ever go undetected, this is why.
    ///
    /// Whenever the model is retrained, verify this again with the fill/centre/fit
    /// switcher in the detection test screen. A mismatch here does not error —
    /// it just returns zero forever.
    nonisolated(unsafe) static var cropAndScale: VNImageCropAndScaleOption = .centerCrop

    /// Why vision is returning nothing, when it is.
    ///
    /// Every failure path here used to `return 0`, which is also a perfectly
    /// valid answer meaning "no mallet". A model that fails to load, a Vision
    /// request that throws, and a bare bilah were therefore indistinguishable —
    /// and after a model swap that ambiguity cost real debugging time. These are
    /// written once and read by the test screen.
    nonisolated(unsafe) static var lastFailure: String?
    nonisolated(unsafe) static var loaded = false

    /// Fails to initialise if the model can't be loaded — the caller then falls
    /// back to audio-only, so vision simply adds nothing rather than crashing.
    init?() {
        do {
            guard let modelURL = Bundle(for: MalletHitClassifier.self).url(forResource: "MalletDetector", withExtension: "mlmodelc") ?? Bundle.main.url(forResource: "MalletDetector", withExtension: "mlmodelc") else {
                Self.loaded = false
                Self.lastFailure = "load: model not found in bundle"
                return nil
            }
            let core = try MLModel(contentsOf: modelURL, configuration: MLModelConfiguration())
            self.model = try VNCoreMLModel(for: core)
            Self.loaded = true
            Self.lastFailure = nil
        } catch {
            Self.loaded = false
            Self.lastFailure = "load: \(error.localizedDescription)"
            print("[MalletHitClassifier] load failed: \(error)")
            return nil
        }
    }

    /// The one loaded model, kept for the life of the process.
    ///
    /// Loading it means compiling the Core ML model and building a
    /// `VNCoreMLModel` around it, which is a few hundred milliseconds — and it
    /// was happening inside `StrikeFusion.init`, i.e. on the way into a play
    /// session, every time. The model does not change, so it is loaded once
    /// (during the splash) and handed out afterwards.
    ///
    /// Sharing one `VNCoreMLModel` is only safe because inference is never
    /// concurrent here: `StrikeFusion` is an actor, `MalletTestView` is on the
    /// main actor, and the two are different screens that cannot be on-screen
    /// at once. If a second concurrent consumer is ever added it must get its
    /// own instance rather than this one.
    nonisolated(unsafe) private static var cached: MalletHitClassifier?
    private static let cacheLock = NSLock()

    static func shared() -> MalletHitClassifier? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached { return cached }
        // A failed load is deliberately NOT cached: it is nearly always a
        // transient resource problem, and remembering it would disable vision
        // for the rest of the launch with no way back.
        let made = MalletHitClassifier()
        cached = made
        return made
    }

    /// The fill/centre/fit options, in the order the tuning screen shows them.
    static let cropScaleOptions: [(name: String, option: VNImageCropAndScaleOption)] = [
        ("fill", .scaleFill), ("centre", .centerCrop), ("fit", .scaleFit)
    ]

    static func applyCropScale(mode: Int) {
        guard cropScaleOptions.indices.contains(mode) else { return }
        cropAndScale = cropScaleOptions[mode].option
    }

    /// P(the crop shows a strike), 0…1. `cropRect` is in `image` pixel space.
    ///
    /// We read P(not-hit) and invert it, so the result is correct regardless of
    /// how the two labels happen to be named/ordered in the model.
    func hitProbability(in image: CGImage, cropRect: CGRect) -> Double {
        guard let cropped = Self.crop(image, to: cropRect) else { return 0 }
        return hitProbability(crop: cropped)
    }

    /// Classify an already-cropped region. Exposed so callers (e.g. the test
    /// screen) can display the exact crop being scored alongside its result.
    func hitProbability(crop cropped: CGImage) -> Double {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = Self.cropAndScale

        let handler = VNImageRequestHandler(cgImage: cropped, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Self.lastFailure = "perform: \(error.localizedDescription)"
            print("[MalletHitClassifier] perform failed: \(error)")
            return 0
        }

        guard let results = request.results as? [VNClassificationObservation] else {
            Self.lastFailure = "results were not classifications"
            return 0
        }
        if let notHit = results.first(where: { $0.identifier == "not-hit" }) {
            Self.lastFailure = nil
            return 1 - Double(notHit.confidence)
        }
        // No `not-hit` label at all: the retrained model's classes are named
        // something else, so the invert above never applies. Report the labels
        // rather than silently falling through to a meaningless best-of.
        Self.lastFailure = "labels: " + results.map(\.identifier).joined(separator: ",")
        // No "not-hit" class present: take the best non-not-hit label directly.
        return Double(results.max(by: { $0.confidence < $1.confidence })?.confidence ?? 0)
    }

    /// Clamp `rect` to the image and crop. Shared so the classifier and any
    /// debug preview crop identically.
    static func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clamped = rect.integral.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else { return nil }
        return image.cropping(to: clamped)
    }
}


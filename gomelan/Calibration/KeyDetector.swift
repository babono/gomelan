//
//  KeyDetector.swift
//  gomelan
//
//  Bilah localisation for the aligning step (PRD §6.4). Finds candidate key
//  rectangles in a single still frame, normalised 0–1 (top-left origin) and
//  sorted left-to-right. Detect ONCE at align, then freeze — never per frame.
//
//  Two backends, chosen automatically:
//   • If a trained "BilahDetector" Core ML object detector is bundled, it is used
//     (robust on the ornate, rope-tied frame — see design discussion). The model
//     is loaded BY FILE at runtime, so the app compiles fine before it exists:
//     drop `BilahDetector.mlmodel` into the target and it activates.
//   • Otherwise it falls back to Vision's generic `VNDetectRectanglesRequest`.
//
//  Either way the result is the same shape, so AligningView needs no change.
//

import Vision
import CoreImage
import CoreML

enum KeyDetector {

    /// The trained bilah object detector, if one is bundled. Loaded once, lazily.
    /// Loading by URL (not the Create ML-generated class) keeps this compiling
    /// before the model is added.
    private static let objectModel: VNCoreMLModel? = {
        guard let url = Bundle.main.url(forResource: "BilahDetector", withExtension: "mlmodelc"),
              let core = try? MLModel(contentsOf: url),
              let vn = try? VNCoreMLModel(for: core) else { return nil }
        return vn
    }()

    /// Whether the trained detector is active (vs. the rectangle fallback). Lets
    /// callers relax their post-filtering when the model is doing the work.
    static var usesTrainedDetector: Bool { objectModel != nil }

    /// Detect candidate bilah rectangles. Returns rects normalised 0–1 (converted
    /// to top-left origin), sorted left-to-right by x.
    static func detectKeys(in image: CGImage,
                           minimumAspectRatio: Float = 0.2,
                           minimumSize: Float = 0.05,
                           minimumConfidence: Float = 0.1) async -> [NormalizedRect] {
        if let model = objectModel {
            return await detectWithModel(model, in: image, minimumConfidence: minimumConfidence)
        }
        return await detectRectangles(in: image,
                                      minimumAspectRatio: minimumAspectRatio,
                                      minimumSize: minimumSize)
    }

    // MARK: - Trained object detector

    private static func detectWithModel(_ model: VNCoreMLModel,
                                        in image: CGImage,
                                        minimumConfidence: Float) async -> [NormalizedRect] {
        await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, _ in
                let objects = (request.results as? [VNRecognizedObjectObservation]) ?? []
                let rects = objects
                    .filter { ($0.labels.first?.confidence ?? 0) >= minimumConfidence }
                    .map { obs -> NormalizedRect in
                        let bb = obs.boundingBox // normalised, bottom-left origin
                        return NormalizedRect(x: Double(bb.minX),
                                              y: Double(1 - bb.maxY), // flip to top-left
                                              w: Double(bb.width),
                                              h: Double(bb.height))
                    }
                    .sorted { $0.x < $1.x }
                continuation.resume(returning: rects)
            }
            // Match how Create ML trained: it SQUASHES each image into the
            // network's fixed square input (non-uniform resize), so we must feed
            // the model the same way or train/inference disagree. (This is also
            // why a wide frame full of thin, close bilah is hard — they collapse
            // to a few pixels in that square; cropping tighter helps more than any
            // option here.)
            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - Rectangle fallback

    private static func detectRectangles(in image: CGImage,
                                         minimumAspectRatio: Float,
                                         minimumSize: Float) async -> [NormalizedRect] {
        await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, _ in
                let observations = (request.results as? [VNRectangleObservation]) ?? []
                let rects = observations
                    .map { obs -> NormalizedRect in
                        let bb = obs.boundingBox // bottom-left origin
                        return NormalizedRect(x: Double(bb.minX),
                                              y: Double(1 - bb.maxY), // flip to top-left
                                              w: Double(bb.width),
                                              h: Double(bb.height))
                    }
                    .sorted { $0.x < $1.x }
                continuation.resume(returning: rects)
            }
            request.minimumAspectRatio = minimumAspectRatio
            request.minimumSize = minimumSize
            request.maximumObservations = 0 // no cap
            request.quadratureTolerance = 20

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
}

//
//  KeyDetector.swift
//  gomelan
//
//  Rectangle detection for calibration (PRD §6.4). Runs VNDetectRectanglesRequest
//  on a single still frame, filters by aspect ratio / size, and sorts the results
//  left-to-right. Detect ONCE at calibration, then freeze — never per frame.
//
//  In v1 the calibration flow is dev-only (§2): this generates the bundled
//  profile; the shipping app loads that profile rather than exposing detection.
//

import Vision
import CoreImage

enum KeyDetector {

    /// Detect candidate key rectangles in a still frame. Returns rects normalised
    /// 0–1 (Vision's origin is bottom-left; converted to top-left here), sorted
    /// left-to-right by centroid x.
    static func detectKeys(in image: CGImage,
                           minimumAspectRatio: Float = 0.2,
                           minimumSize: Float = 0.05) async -> [NormalizedRect] {
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

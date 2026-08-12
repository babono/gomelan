//
//  MalletHitClassifier.swift
//  gomelan
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

final class MalletHitClassifier {

    private let model: VNCoreMLModel

    /// How Vision fits the (non-square) key crop into the model's 360×360 input.
    ///
    /// `.scaleFill` (squash) matches how Create ML trained this model: it's built
    /// on Vision's FeaturePrint.Scene extractor, whose crop-and-scale default is
    /// scaleFill, so the tall-thin bar crops in the dataset were squashed to the
    /// square input. We squash the same way here so train/inference agree. Flip to
    /// `.centerCrop` only if we later confirm the dataset was prepared differently.
    private let cropAndScale: VNImageCropAndScaleOption = .scaleFill

    /// Fails to initialise if the model can't be loaded — the caller then falls
    /// back to audio-only, so vision simply adds nothing rather than crashing.
    init?() {
        guard let core = try? MalletDetector(configuration: MLModelConfiguration()),
              let vn = try? VNCoreMLModel(for: core.model) else {
            return nil
        }
        self.model = vn
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
        request.imageCropAndScaleOption = cropAndScale

        let handler = VNImageRequestHandler(cgImage: cropped, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return 0
        }

        guard let results = request.results as? [VNClassificationObservation] else { return 0 }
        if let notHit = results.first(where: { $0.identifier == "not-hit" }) {
            return 1 - Double(notHit.confidence)
        }
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

/// Converts an overlay-space normalised rect (portrait, top-left origin) into a
/// pixel rect in the camera frame, undoing the preview's `.resizeAspectFill`.
///
/// The overlay is drawn full-screen over an aspect-fill preview, so the frame is
/// scaled up and cropped to fill the view. A rect placed over the preview must be
/// mapped back through that same crop to land on the right pixels.
enum CropMapper {
    /// Maps the user's dragged key rect straight into frame pixels — the crop
    /// keeps the aspect ratio the user set during aligning. The model's 360×360
    /// square input is reconciled at the resize step (`.centerCrop`), not by
    /// reshaping the crop here.
    static func bufferRect(overlay: NormalizedRect,
                           bufferSize: CGSize,
                           viewSize: CGSize) -> CGRect {
        guard bufferSize.width > 0, bufferSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return .zero }

        // Aspect-fill: the buffer is scaled by the larger ratio, then centre-cropped.
        let scale = max(viewSize.width / bufferSize.width,
                        viewSize.height / bufferSize.height)
        let offsetX = (bufferSize.width * scale - viewSize.width) / 2
        let offsetY = (bufferSize.height * scale - viewSize.height) / 2

        func toBuffer(_ nx: Double, _ ny: Double) -> CGPoint {
            let viewX = nx * viewSize.width
            let viewY = ny * viewSize.height
            return CGPoint(x: (viewX + offsetX) / scale,
                           y: (viewY + offsetY) / scale)
        }

        let topLeft = toBuffer(overlay.x, overlay.y)
        let bottomRight = toBuffer(overlay.x + overlay.w, overlay.y + overlay.h)
        return CGRect(x: topLeft.x,
                      y: topLeft.y,
                      width: bottomRight.x - topLeft.x,
                      height: bottomRight.y - topLeft.y)
    }

    /// The inverse of `bufferRect`: takes a rect normalised to the camera buffer
    /// (Vision's output, 0–1 of the image, top-left origin) and returns it in the
    /// overlay's view-normalised space, undoing the same aspect-fill crop. Used to
    /// place auto-detected bilah onto the draggable overlay.
    static func overlayRect(bufferNormalized r: NormalizedRect,
                            bufferSize: CGSize,
                            viewSize: CGSize) -> NormalizedRect {
        guard bufferSize.width > 0, bufferSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return r }

        let scale = max(viewSize.width / bufferSize.width,
                        viewSize.height / bufferSize.height)
        let offsetX = (bufferSize.width * scale - viewSize.width) / 2
        let offsetY = (bufferSize.height * scale - viewSize.height) / 2

        func toOverlay(_ bnx: Double, _ bny: Double) -> CGPoint {
            let bufX = bnx * bufferSize.width
            let bufY = bny * bufferSize.height
            return CGPoint(x: (bufX * scale - offsetX) / viewSize.width,
                           y: (bufY * scale - offsetY) / viewSize.height)
        }

        let tl = toOverlay(r.x, r.y)
        let br = toOverlay(r.x + r.w, r.y + r.h)
        return NormalizedRect(x: Double(tl.x), y: Double(tl.y),
                              w: Double(br.x - tl.x), h: Double(br.y - tl.y))
    }
}

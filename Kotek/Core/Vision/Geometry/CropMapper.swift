//
//  CropMapper.swift
//  Kotek
//
//  Converts an overlay-space normalised rect (portrait, top-left origin) into a
//  pixel rect in the camera frame, undoing the preview's `.resizeAspectFill`.
//
//  The overlay is drawn full-screen over an aspect-fill preview, so the frame is
//  scaled up and cropped to fill the view. A rect placed over the preview must be
//  mapped back through that same crop to land on the right pixels.
//

import CoreGraphics
import Foundation

/// Converts an overlay-space normalised rect (portrait, top-left origin) into a
/// pixel rect in the camera frame, undoing the preview's `.resizeAspectFill`.
///
/// The overlay is drawn full-screen over an aspect-fill preview, so the frame is
/// scaled up and cropped to fill the view. A rect placed over the preview must be
/// mapped back through that same crop to land on the right pixels.
nonisolated enum CropMapper {
    /// Maps the user's dragged key rect straight into frame pixels — the crop
    /// keeps the aspect ratio the user set during aligning. Reshaping to the
    /// model's square input happens later, in `MalletHitClassifier` via
    /// `.scaleFill`, which SQUASHES the rect rather than cropping it.
    ///
    /// (This comment previously said `.centerCrop`. It never matched the code,
    /// and the difference is not cosmetic: on a tall-thin bilah crop `.centerCrop`
    /// would take a square from the middle and discard most of the bar.)
    ///
    /// One consequence worth knowing when preparing training data: because the
    /// user chooses each rect's aspect ratio during aligning, the AMOUNT of
    /// squash varies per key and per calibration. The same physical strike looks
    /// different to the model depending on how the rect was drawn, so a training
    /// set gathered at one aspect ratio only calibrates the model for that one.
    /// Collect through this path, at the aspect ratios users actually produce.
    static func bufferRect(
        overlay: NormalizedRect,
        bufferSize: CGSize,
        viewSize: CGSize
    ) -> CGRect {
        guard bufferSize.width > 0, bufferSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return .zero }

        // Aspect-fill: the buffer is scaled by the larger ratio, then centre-cropped.
        let scale = max(
            viewSize.width / bufferSize.width,
            viewSize.height / bufferSize.height
        )
        let offsetX = (bufferSize.width * scale - viewSize.width) / 2
        let offsetY = (bufferSize.height * scale - viewSize.height) / 2

        func toBuffer(_ nx: Double, _ ny: Double) -> CGPoint {
            let viewX = nx * viewSize.width
            let viewY = ny * viewSize.height
            return CGPoint(
                x: (viewX + offsetX) / scale,
                y: (viewY + offsetY) / scale
            )
        }

        let topLeft = toBuffer(overlay.x, overlay.y)
        let bottomRight = toBuffer(overlay.x + overlay.w, overlay.y + overlay.h)
        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )
    }

    /// The point form of `overlayRect`, for a detector that reports positions
    /// rather than boxes — the marker tracker finds a mallet tip, not a crop.
    ///
    /// Written as its own function rather than by passing a zero-sized rect
    /// through `overlayRect`: that works, but it reads as a trick and the
    /// degenerate width is exactly the kind of thing a later edit "fixes".
    static func overlayPoint(
        bufferNormalized p: CGPoint,
        bufferSize: CGSize,
        viewSize: CGSize
    ) -> CGPoint {
        guard bufferSize.width > 0, bufferSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return p }

        let scale = max(
            viewSize.width / bufferSize.width,
            viewSize.height / bufferSize.height
        )
        let offsetX = (bufferSize.width * scale - viewSize.width) / 2
        let offsetY = (bufferSize.height * scale - viewSize.height) / 2

        return CGPoint(
            x: (p.x * bufferSize.width * scale - offsetX) / viewSize.width,
            y: (p.y * bufferSize.height * scale - offsetY) / viewSize.height
        )
    }

    /// The inverse of `bufferRect`: takes a rect normalised to the camera buffer
    /// (Vision's output, 0–1 of the image, top-left origin) and returns it in the
    /// overlay's view-normalised space, undoing the same aspect-fill crop. Used to
    /// place auto-detected bilah onto the draggable overlay.
    static func overlayRect(
        bufferNormalized r: NormalizedRect,
        bufferSize: CGSize,
        viewSize: CGSize
    ) -> NormalizedRect {
        guard bufferSize.width > 0, bufferSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return r }

        let scale = max(
            viewSize.width / bufferSize.width,
            viewSize.height / bufferSize.height
        )
        let offsetX = (bufferSize.width * scale - viewSize.width) / 2
        let offsetY = (bufferSize.height * scale - viewSize.height) / 2

        func toOverlay(_ bnx: Double, _ bny: Double) -> CGPoint {
            let bufX = bnx * bufferSize.width
            let bufY = bny * bufferSize.height
            return CGPoint(
                x: (bufX * scale - offsetX) / viewSize.width,
                y: (bufY * scale - offsetY) / viewSize.height
            )
        }

        let tl = toOverlay(r.x, r.y)
        let br = toOverlay(r.x + r.w, r.y + r.h)
        return NormalizedRect(
            x: Double(tl.x),
            y: Double(tl.y),
            w: Double(br.x - tl.x),
            h: Double(br.y - tl.y)
        )
    }
}

//
//  NormalizedRect.swift
//  Kotek
//
//  Normalised 0–1 coordinate primitives against the video frame (PRD §7).
//  Used across vision detection, camera projection, calibration masks,
//  and instrument profiles.
//

import CoreGraphics
import Foundation

/// A rectangle normalised 0–1 against the video frame, so the overlay survives
/// resolution and orientation changes (PRD §7).
nonisolated struct NormalizedRect: Codable, Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    /// Maps this normalised rect into a concrete view-space rect.
    func rect(in size: CGSize) -> CGRect {
        CGRect(
            x: x * size.width,
            y: y * size.height,
            width: w * size.width,
            height: h * size.height
        )
    }

    /// The rect's four corners, ordered top-left, top-right, bottom-right,
    /// bottom-left — the seed quad when a key has no free-corner shape yet.
    var corners: [NormalizedPoint] {
        [
            NormalizedPoint(x: x, y: y),
            NormalizedPoint(x: x + w, y: y),
            NormalizedPoint(x: x + w, y: y + h),
            NormalizedPoint(x: x, y: y + h)
        ]
    }

    /// The axis-aligned bounding box of a quad — what downstream (overlay, crop)
    /// consumes, so the rest of the app stays rect-based.
    static func boundingBox(of pts: [NormalizedPoint]) -> NormalizedRect {
        guard let first = pts.first else { return NormalizedRect(x: 0, y: 0, w: 0, h: 0) }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in pts {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return NormalizedRect(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }
}

/// A point normalised 0–1 against the video frame. Four of these make the
/// free-corner quad the aligning step edits (CamScanner-style).
nonisolated struct NormalizedPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

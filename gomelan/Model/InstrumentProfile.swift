//
//  InstrumentProfile.swift
//  gomelan
//
//  The per-instrument profile. Every village in Bali tunes differently, so key
//  positions and pitches are never hardcoded in logic — they live here, produced
//  by the calibration flow (§13.3) and shipped as a bundled default (§2).
//

import Foundation
import CoreGraphics

/// A rectangle normalised 0–1 against the video frame, so the overlay survives
/// resolution and orientation changes (PRD §7).
struct NormalizedRect: Codable, Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    var cgRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }

    /// Maps this normalised rect into a concrete view-space rect.
    func rect(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width,
               y: y * size.height,
               width: w * size.width,
               height: h * size.height)
    }
}

/// One calibrated key: where it is in frame, and how it sounds.
struct InstrumentKey: Codable, Identifiable, Equatable {
    var index: Int
    var rect: NormalizedRect
    var fundamentalHz: Double
    var harmonics: [Double]
    var decayMs: Int
    var confidence: Double
    var samplePath: String?

    var id: Int { index }
}

/// A calibrated instrument. v1 ships exactly one (our gangsa), but the shape is
/// per-instrument by design (PRD §2, §7).
struct InstrumentProfile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var keyCount: Int
    var createdAt: String
    var keys: [InstrumentKey]
}

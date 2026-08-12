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

    /// L2-normalised spectral fingerprint, `fpBands` long — this is what the key
    /// is actually recognised by. `fundamentalHz` and `harmonics` are kept for
    /// display only: bronze is inharmonic, so a single fundamental does not
    /// identify a key reliably and pitch cannot be assumed across instruments.
    ///
    /// Optional so profiles saved before fingerprinting still decode; a key
    /// without one simply cannot be matched until it is recalibrated.
    var fingerprint: [Float]?

    var id: Int { index }

    var isCalibrated: Bool { !(fingerprint?.isEmpty ?? true) }
}

/// A calibrated instrument. v1 ships exactly one (our gangsa), but the shape is
/// per-instrument by design (PRD §2, §7).
struct InstrumentProfile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var keyCount: Int
    var createdAt: String
    var keys: [InstrumentKey]

    /// How many of the keys have a usable template.
    var calibratedKeyCount: Int { keys.filter(\.isCalibrated).count }

    var isFullyCalibrated: Bool { !keys.isEmpty && calibratedKeyCount == keys.count }

    /// Resize the profile to `count` keys, laying them out evenly across the
    /// frame as a starting point for manual alignment.
    ///
    /// Existing keys keep their rect and template so changing the count does not
    /// silently discard a calibration the user already did; only added keys get
    /// generated positions.
    mutating func resize(to count: Int) {
        let generated = InstrumentProfile.layout(count: count)
        var next: [InstrumentKey] = []
        for i in 0..<count {
            if i < keys.count {
                next.append(keys[i])
            } else {
                next.append(generated[i])
            }
        }
        keys = next
        keyCount = count
    }

    /// Evenly spaced key outlines across the middle of the frame. Gangsa keys run
    /// left to right from longest/lowest to shortest/highest, so the outlines are
    /// graduated in height to match — it makes the overlay easier to line up.
    static func layout(count: Int) -> [InstrumentKey] {
        guard count > 0 else { return [] }
        let margin = 0.05
        let usable = 1.0 - margin * 2
        let pitch = usable / Double(count)
        let width = pitch * 0.8

        return (0..<count).map { i in
            // Single key sits mid-range rather than at the "tallest" extreme.
            let t = count > 1 ? Double(i) / Double(count - 1) : 0.5
            return InstrumentKey(
                index: i,
                rect: NormalizedRect(x: margin + Double(i) * pitch + (pitch - width) / 2,
                                     y: 0.33 + 0.09 * t,
                                     w: width,
                                     h: 0.44 - 0.18 * t),
                fundamentalHz: 0,
                harmonics: [],
                decayMs: 1500,
                confidence: 0,
                samplePath: nil,
                fingerprint: nil
            )
        }
    }
}

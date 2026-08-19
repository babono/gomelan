//
//  InstrumentProfile.swift
//  Kotek
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

    /// The rect's four corners, ordered top-left, top-right, bottom-right,
    /// bottom-left — the seed quad when a key has no free-corner shape yet.
    var corners: [NormalizedPoint] {
        [NormalizedPoint(x: x, y: y),
         NormalizedPoint(x: x + w, y: y),
         NormalizedPoint(x: x + w, y: y + h),
         NormalizedPoint(x: x, y: y + h)]
    }

    /// The axis-aligned bounding box of a quad — what downstream (overlay, crop)
    /// consumes, so the rest of the app stays rect-based.
    static func boundingBox(of pts: [NormalizedPoint]) -> NormalizedRect {
        guard let first = pts.first else { return NormalizedRect(x: 0, y: 0, w: 0, h: 0) }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return NormalizedRect(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }
}

/// A point normalised 0–1 against the video frame. Four of these make the
/// free-corner quad the aligning step edits (CamScanner-style).
struct NormalizedPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

/// One calibrated key: where it is in frame, and how it sounds.
struct InstrumentKey: Codable, Identifiable, Equatable {
    var index: Int
    var rect: NormalizedRect
    /// Optional free-corner quad set during aligning (top-left, top-right,
    /// bottom-right, bottom-left). When present it's the editable shape; `rect`
    /// is kept as its bounding box so overlay/detection stay rect-based. nil ⇒
    /// the key is a plain axis-aligned rect.
    var corners: [NormalizedPoint]? = nil
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

    /// LINEAR band template, `fpBands` long — the NNLS dictionary atom for this
    /// key. Separate from `fingerprint` because that one is compressed (^0.7)
    /// and NNLS needs a vector that adds: see `Fingerprinter.linearBands`.
    ///
    /// Nobody strikes each key to produce this. It accumulates during play from
    /// strikes the camera identified confidently, so it appears on its own after
    /// a few passes and gets better every session — see `KeyDecomposer`.
    var linearTemplate: [Float]?

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
    /// Generic gangsa-strike baseline template (L2-normalised float vector).
    var strikeBaseline: [Float]? = nil
    /// Timestamp when this profile was last used.
    var lastUsedAt: String? = nil

    /// Whether this instrument has a learned strike-sound baseline.
    var hasLearnedBaseline: Bool { !(strikeBaseline?.isEmpty ?? true) }

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

    /// Evenly spaced key outlines across the middle of the frame.
    static func layout(count: Int) -> [InstrumentKey] {
        layout(count: count, in: NormalizedRect(x: 0.05, y: 0.28, w: 0.90, h: 0.46))
    }

    /// Evenly spaced key outlines filling `region` — the area the player framed
    /// the instrument into, so the starting row is already about right.
    ///
    /// Gangsa bilah run left to right from lowest to highest. Seen from above
    /// they stay much the same length and mostly get NARROWER, so the row tapers
    /// in width and holds its height: a graduated-height row read as a staircase
    /// against the real instrument.
    static func layout(count: Int, in region: NormalizedRect) -> [InstrumentKey] {
        guard count > 0 else { return [] }
        let pitch = region.w / Double(count)

        return (0..<count).map { i in
            let t = count > 1 ? Double(i) / Double(count - 1) : 0.5
            let width = pitch * (0.82 - 0.16 * t)
            return InstrumentKey(
                index: i,
                rect: NormalizedRect(x: region.x + Double(i) * pitch + (pitch - width) / 2,
                                     y: region.y + region.h * 0.16,
                                     w: width,
                                     h: region.h * 0.68),
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

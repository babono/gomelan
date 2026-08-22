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
    /// Timestamp when this profile was last PLAYED — written when a session
    /// ends, not when the card is tapped. It is what orders the rail.
    var lastUsedAt: String? = nil

    /// Sessions finished on this instrument, and the notes in them that landed
    /// (right key, near enough the beat). Together they are the grade.
    ///
    /// Optional rather than `= 0` for a reason that has already cost this app
    /// once: synthesized `Decodable` does NOT fall back to a property's default
    /// when the key is missing, and `ProfileStore.loadAll` decodes the whole
    /// list with `try?`. A non-optional new field would make every profile
    /// saved before this build throw, and take the player's entire instrument
    /// list down with it. Same reason `strikeBaseline` and `fingerprint` are
    /// optional.
    var sessionCount: Int? = nil
    var accurateNotes: Int? = nil

    /// Whether this instrument has a learned strike-sound baseline.
    var hasLearnedBaseline: Bool { !(strikeBaseline?.isEmpty ?? true) }

    /// How many of the keys have a usable template.
    var calibratedKeyCount: Int { keys.filter(\.isCalibrated).count }

    var isFullyCalibrated: Bool { !keys.isEmpty && calibratedKeyCount == keys.count }

    var sessionsPlayed: Int { sessionCount ?? 0 }
    var notesLanded: Int { accurateNotes ?? 0 }

    /// This instrument's grade — see `Mastery`.
    var mastery: Mastery { Mastery(notesLanded: notesLanded) }

    var hasBeenPlayed: Bool { lastUsedAt != nil || sessionsPlayed > 0 }

    var lastPlayedDate: Date? { InstrumentProfile.date(from: lastUsedAt) }

    /// The sort key for the rail: last played, falling back to when the
    /// instrument was created.
    ///
    /// The fallback is the whole point. Sorting purely on "last played" buries
    /// an instrument the moment you finish setting it up — four steps of work
    /// and it lands at the far end of the rail behind everything you have ever
    /// used, which is exactly when you most want it in front of you.
    var recency: Date {
        lastPlayedDate ?? InstrumentProfile.date(from: createdAt) ?? .distantPast
    }

    /// ISO8601 in, `Date` out. A free function rather than a cached
    /// `ISO8601DateFormatter`: this target is MainActor by default, so a shared
    /// formatter would be main-actor isolated — and `ProfileStore`, which sorts
    /// by these dates and is deliberately `nonisolated`, could not touch it.
    static func date(from iso: String?) -> Date? {
        guard let iso else { return nil }
        return try? Date(iso, strategy: .iso8601)
    }

    static func nowISO() -> String { Date().formatted(.iso8601) }

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

/// How far an instrument has been taken — the grade on its card.
///
/// Counted in notes that LANDED (right key, near enough the beat), not sessions
/// or minutes. Time-based grades are farmable by leaving the phone on the stand,
/// and session counts reward starting rather than playing; this rewards the one
/// thing the app is for. Practice mode adds nothing to it on purpose — practice
/// waits for you, so every note lands eventually, and a grade you can reach by
/// being slow is not a grade.
///
/// The rungs are the sections of a Balinese composition, in the order a piece
/// moves through them: a free opening, the beginning proper, the long body, the
/// quickening, the close. A piece gets faster and denser as it goes, which is
/// the same shape a player's arc has — and it teaches five words worth knowing
/// instead of "Level 3".
struct Mastery: Equatable {
    enum Rank: Int, CaseIterable {
        case gineman, pengawit, pengawak, pengecet, pekaad

        /// Notes at which this rung begins.
        ///
        /// Set against what a session actually produces now that practice loops
        /// until you stop it. Ubitan Nyendok is a 2-second cycle with four polos
        /// strokes in it — two strokes a second — so twenty minutes at a decent
        /// hit rate is on the order of 1,400 landed notes. The first rungs were
        /// written for a scored run of eight cycles (~64 notes) and a single
        /// evening would have taken you past the top of the ladder.
        ///
        /// Pengawit lands within one solid session, so the ladder starts moving
        /// early; Pekaad is a few dozen of them, which is the months of practice
        /// the name is meant to stand for.
        var threshold: Int {
            switch self {
            case .gineman:  return 0
            case .pengawit: return 1_000
            case .pengawak: return 5_000
            case .pengecet: return 15_000
            case .pekaad:   return 40_000
            }
        }

        var title: String {
            switch self {
            case .gineman:  return "Gineman"
            case .pengawit: return "Pengawit"
            case .pengawak: return "Pengawak"
            case .pengecet: return "Pengecet"
            case .pekaad:   return "Pekaad"
            }
        }

        /// One line of English, because a rank nobody can translate is a badge
        /// rather than a lesson.
        var gloss: String {
            switch self {
            case .gineman:  return "the free opening"
            case .pengawit: return "the beginning"
            case .pengawak: return "the body"
            case .pengecet: return "the quickening"
            case .pekaad:   return "the close"
            }
        }
    }

    let notes: Int
    let rank: Rank

    init(notesLanded: Int) {
        let n = max(0, notesLanded)
        notes = n
        rank = Rank.allCases.last { n >= $0.threshold } ?? .gineman
    }

    var next: Rank? { Rank(rawValue: rank.rawValue + 1) }

    /// 0…1 through the current rung. The top rung reads full: there is nothing
    /// left to fill towards, and a bar that never completes is a treadmill.
    var progress: Double {
        guard let next else { return 1 }
        let span = Double(next.threshold - rank.threshold)
        guard span > 0 else { return 1 }
        return min(1, max(0, Double(notes - rank.threshold) / span))
    }

    var notesToNext: Int? {
        guard let next else { return nil }
        return max(0, next.threshold - notes)
    }
}

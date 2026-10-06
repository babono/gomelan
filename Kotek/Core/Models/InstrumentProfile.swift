//
//  InstrumentProfile.swift
//  Kotek
//
//  The per-instrument profile. Every village in Bali tunes differently, so key
//  positions and pitches are never hardcoded in logic — they live here, produced
//  by the calibration flow (§13.3) and shipped as a bundled default (§2).
//

import Foundation

/// One calibrated key: where it is in frame, and how it sounds.
nonisolated struct InstrumentKey: Codable, Identifiable, Equatable, Sendable {
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

    /// How many strikes went into `linearTemplate`.
    ///
    /// Saved because the atom is only trusted after four of them, and without a
    /// count there was no way to write down a key that had reached two — so it
    /// was not written at all, and the next session started that key from zero.
    /// A dictionary that can only be saved once it is finished is one that
    /// mostly never gets saved.
    ///
    /// Optional for the usual reason: synthesized `Decodable` does not fall
    /// back to a default for a missing key, and `ProfileStore.loadAll` decodes
    /// the whole list with `try?`. Profiles written before this build read as
    /// nil and are taken at face value — see `learnedAtom`.
    var linearTemplateCount: Int?

    /// The learned spectrum with its example count, if there is one.
    ///
    /// A profile from before the count existed is assumed fully trusted: it was
    /// only ever written at four examples, because that was the old threshold
    /// to be written at all.
    var learnedAtom: LearnedAtom? {
        guard let linearTemplate, !linearTemplate.isEmpty else { return nil }
        return LearnedAtom(bands: linearTemplate,
                           examples: linearTemplateCount ?? KeyDecomposer.strikesToTrustAtom)
    }

    var id: Int { index }

    var isCalibrated: Bool { !(fingerprint?.isEmpty ?? true) }
}

/// The best a figure has ever been played on this gangsa.
///
/// One per figure PER HALF PER SPEED, because that is the only comparison that
/// means anything — polos at half tempo and sangsih at 1.5× are not the same
/// feat, and a single "best on Ubitan Nyendok" would silently be whichever of
/// them was easiest.
///
/// An array rather than a keyed dictionary on purpose: `ProfileStore` encodes
/// with `.convertToSnakeCase`, which rewrites DICTIONARY keys as well as
/// property names, and it would quietly mangle a composite key like
/// "ubitannyendok-polos@1.0" on the way to disk.
nonisolated struct PatternRecord: Codable, Equatable, Identifiable, Sendable {
    var kotekanId: String
    /// `KotekanHalf.rawValue` — stored as a string so the model layer does not
    /// have to import the figure vocabulary to decode a profile.
    var half: String
    var tempo: Double
    /// Best accuracy over `SongResult.scoringWindow` consecutive cycles, 0…1.
    var accuracy: Double
    var setAt: String

    var id: String { "\(kotekanId)·\(half)@\(tempo)" }
}

/// Which gangsa this is. The two are the same instrument an octave apart —
/// kantilan above pemade — so nothing in detection or play depends on it; it
/// names the card and the `gangsa_type` column.
nonisolated enum GangsaType: String, Codable, CaseIterable, Identifiable, Sendable {
    case pemade
    case kantilan

    var id: String { rawValue }
    var title: String { self == .pemade ? "Pemade" : "Kantilan" }
}

/// A calibrated instrument. v1 ships exactly one (our gangsa), but the shape is
/// per-instrument by design (PRD §2, §7).
nonisolated struct InstrumentProfile: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var keyCount: Int
    /// Optional for the decoding reason given on `sessionCount` below. Read
    /// through `type`, which falls back to pemade.
    var gangsaType: GangsaType? = nil
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

    /// Personal bests per figure. Optional for the same decoding reason as the
    /// counters above.
    var records: [PatternRecord]? = nil

    /// Whether this instrument has a learned strike-sound baseline.
    var hasLearnedBaseline: Bool { !(strikeBaseline?.isEmpty ?? true) }

    /// How many of the keys have a usable template.
    var calibratedKeyCount: Int { keys.filter(\.isCalibrated).count }

    var isFullyCalibrated: Bool { !keys.isEmpty && calibratedKeyCount == keys.count }

    var type: GangsaType { gangsaType ?? .pemade }

    var sessionsPlayed: Int { sessionCount ?? 0 }
    var notesLanded: Int { accurateNotes ?? 0 }

    /// This instrument's grade — see `Mastery`.
    var mastery: Mastery { Mastery(notesLanded: notesLanded) }

    var hasBeenPlayed: Bool { lastUsedAt != nil || sessionsPlayed > 0 }

    /// The record for exactly this figure, half and speed.
    func record(kotekanId: String, half: String, tempo: Double) -> PatternRecord? {
        records?.first { $0.kotekanId == kotekanId && $0.half == half && $0.tempo == tempo }
    }

    /// The best this figure has been played at ALL, whichever half and speed it
    /// was — what the picker card shows. It carries its conditions with it, so
    /// a 0.75× best is never mistaken for a full-tempo one.
    func bestRecord(kotekanId: String) -> PatternRecord? {
        records?.filter { $0.kotekanId == kotekanId }.max { $0.accuracy < $1.accuracy }
    }

    /// File a result. Returns the record it beat, or nil if it did not beat one
    /// — which is not the same as there being no record, so callers check
    /// `record(...)` first if they need to tell a first time from a near miss.
    @discardableResult
    mutating func noteRecord(kotekanId: String, half: String, tempo: Double,
                             accuracy: Double) -> Bool {
        var all = records ?? []
        let fresh = PatternRecord(kotekanId: kotekanId, half: half, tempo: tempo,
                                  accuracy: accuracy, setAt: InstrumentProfile.nowISO())
        if let idx = all.firstIndex(where: {
            $0.kotekanId == kotekanId && $0.half == half && $0.tempo == tempo
        }) {
            guard accuracy > all[idx].accuracy else { return false }
            all[idx] = fresh
        } else {
            all.append(fresh)
        }
        records = all
        return true
    }

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


//
//  PlayTypes.swift
//  Kotek
//
//  Core session and render types for the PlayEngine and its overlays.
//

import Foundation
import SwiftUI

enum SessionPhase: Equatable {
    case countIn // gong only, one colotomic cycle
    case userTurn // the figure is going round; you play

    var isUserPlaying: Bool {
        self == .userTurn
    }
}

/// What the overlay should draw for a single key this frame.
struct KeyRenderState: Equatable {
    var fill: Double = 0 // the NEAREST stroke's progress, 0…1 — the bar that fills from the bottom
    var strikeNow: Bool = false // solid highlight pulse
    /// You got that one. The instrument says exactly one thing about a stroke
    /// you have played — green, or nothing at all.
    var hit: Bool = false
    var damp: Bool = false // dashed damp hint on the previous key (§5.5)
    /// Every upcoming stroke on this bilah that is inside the cue window,
    /// nearest first — one ring each, nested.
    var approaches: [Double] = []
}

/// Which of the two interlocking halves a note belongs to.
enum NoteVoice: Equatable {
    case yours // the half you are learning
    case partner // the half the app plays beside you
}

/// One stroke of the figure, placed on the CYCLE rather than on a moving
/// stream (§13.5). `x` is where in the pattern it falls, 0…1, and it never
/// moves — the playhead does.
struct CycleNote: Identifiable, Equatable {
    let id: String
    let keyIndex: Int
    let voice: NoteVoice
    let x: Double // 0…1 through the pattern
    let width: Double // the stroke's own duration, same units
    /// Set once your note has been judged this pass; cleared at the turn.
    var outcome: JudgementResult?
    /// The stroke due right now — what the bilah overlay is lighting.
    var isCurrent: Bool = false
    /// Both halves strike this key on this slot.
    var isUnison: Bool = false
}

struct TrackMarker: Identifiable, Equatable {
    enum Kind: Equatable { case gong, kempur, kajar, beat }
    let id: Int
    let kind: Kind
    let xFraction: Double
}

/// A stroke's verdict, said once on the bilah and gone.
struct Floater: Identifiable, Equatable {
    let id: Int
    let keyIndex: Int
    let label: FloaterLabel
    /// Host time, matched against `renderNow`.
    let bornAt: Double
}

enum FloaterLabel: Int, CaseIterable {
    case perfect, goodEarly, goodLate, late, miss, wrongKey, unmatched

    var text: String {
        switch self {
        case .perfect: String(localized: "PERFECT")
        case .goodEarly: String(localized: "GOOD · early")
        case .goodLate: String(localized: "GOOD · late")
        case .late: String(localized: "LATE")
        case .miss: String(localized: "MISS")
        case .wrongKey: String(localized: "WRONG BAR")
        case .unmatched: String(localized: "NO NOTE DUE")
        }
    }

    /// Canvas symbol identity, in an Int range no bilah can reach.
    var symbolID: Int {
        1000 + rawValue
    }

    /// Bucketed rather than showing the millisecond error, so every label is
    /// one of seven and can be pre-rendered as a Canvas symbol.
    static func from(_ result: JudgementResult, timingErrorMs: Double) -> FloaterLabel {
        switch result {
        case .perfect: .perfect
        case .good: timingErrorMs > 0 ? .goodEarly : .goodLate
        case .lateEarly: .late
        case .miss: .miss
        case .wrongKey: .wrongKey
        }
    }
}

/// One stroke on the waterfall, placed by how long until it lands.
struct FallingNote: Identifiable, Equatable {
    let id: String
    let keyIndex: Int
    let voice: NoteVoice
    /// Milliseconds until it reaches the bilah; negative once it has passed.
    let msAhead: Double
    let durationMs: Double
    var outcome: JudgementResult?
    /// Whether the left hand pinches THIS bilah as soon as the note ends
    /// (§5.5). False for the partner's half, and when the next stroke of the same half is this same bilah: the
    /// mallet re-strikes a bar that is still ringing, so there is nothing to
    /// damp in between.
    ///
    /// It used to be the previous stroke's bilah, pinched as this one was
    /// struck. That made the damp wait for the next note, so a note before a
    /// rest rang on through the rest with no damp shown at all. It rings
    /// through the rest now too (`Kotekan.makeSong`), but its own damp shows
    /// at the end of it — or sooner, where Studio set a damp point
    /// (`Note.damped`), which damps a re-struck bilah as well.
    ///
    /// The musical fact only: whether it is SHOWN is `DampGuide`, applied by
    /// the views, so it can change mid-session from the pause screen.
    let dampsAfter: Bool
}

/// A beat rule on the waterfall. `strong` every four beats, on the kajar.
struct FallingBeat: Identifiable, Equatable {
    let id: Int
    let msAhead: Double
    let strong: Bool
}

/// The turn of the cycle on the waterfall: where pass `number` begins.
struct FallingCycle: Equatable {
    let number: Int
    let msAhead: Double
}

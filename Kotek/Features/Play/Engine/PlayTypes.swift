//
//  PlayTypes.swift
//  Kotek
//
//  Core session and render types for the PlayEngine and its overlays.
//

import Foundation
import SwiftUI

enum SessionPhase: Equatable {
    case countIn    // gong only, one colotomic cycle
    case userTurn   // the figure is going round; you play

    var isUserPlaying: Bool { self == .userTurn }
}

/// What the overlay should draw for a single key this frame.
struct KeyRenderState: Equatable {
    var fill: Double = 0        // the NEAREST stroke's progress, 0…1 — the bar that fills from the bottom
    var strikeNow: Bool = false // solid highlight pulse
    /// You got that one. The instrument says exactly one thing about a stroke
    /// you have played — green, or nothing at all.
    var hit: Bool = false
    var damp: Bool = false      // dashed damp hint on the previous key (§5.5)
    /// Every upcoming stroke on this bilah that is inside the cue window,
    /// nearest first — one ring each, nested.
    var approaches: [Double] = []
}

/// Which of the two interlocking halves a note belongs to.
enum NoteVoice: Equatable {
    case yours      // the half you are learning
    case partner    // the half the app plays beside you
}

/// One stroke of the figure, placed on the CYCLE rather than on a moving
/// stream (§13.5). `x` is where in the pattern it falls, 0…1, and it never
/// moves — the playhead does.
struct CycleNote: Identifiable, Equatable {
    let id: String
    let keyIndex: Int
    let voice: NoteVoice
    let x: Double               // 0…1 through the pattern
    let width: Double           // the stroke's own duration, same units
    /// Set once your note has been judged this pass; cleared at the turn.
    var outcome: JudgementResult? = nil
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

enum FloaterLabel: Int, CaseIterable, Sendable {
    case perfect, goodEarly, goodLate, late, miss, wrongKey, unmatched

    var text: String {
        switch self {
        case .perfect:   return "PERFECT"
        case .goodEarly: return "GOOD · early"
        case .goodLate:  return "GOOD · late"
        case .late:      return "LATE"
        case .miss:      return "MISS"
        case .wrongKey:  return "WRONG BAR"
        case .unmatched: return "NO NOTE DUE"
        }
    }

    /// Canvas symbol identity, in an Int range no bilah can reach.
    var symbolID: Int { 1_000 + rawValue }

    /// Bucketed rather than showing the millisecond error, so every label is
    /// one of seven and can be pre-rendered as a Canvas symbol.
    static func from(_ result: JudgementResult, timingErrorMs: Double) -> FloaterLabel {
        switch result {
        case .perfect:   return .perfect
        case .good:      return timingErrorMs > 0 ? .goodEarly : .goodLate
        case .lateEarly: return .late
        case .miss:      return .miss
        case .wrongKey:  return .wrongKey
        }
    }
}

//
//  Mastery.swift
//  Kotek
//
//  The player progression model for an instrument (PRD §5).
//  Counted in notes that landed accurately, advancing through the
//  traditional Balinese ranks.
//

import Foundation

/// How far an instrument has been taken — the grade on its card.
///
/// Counted in notes that LANDED (right key, near enough the beat), not sessions
/// or minutes. Time-based grades are farmable by leaving the phone on the stand,
/// and session counts reward starting rather than playing; this rewards the one
/// thing the app is for. Practice mode adds nothing to it on purpose — practice
/// waits for you, so every note lands eventually, and a grade you can reach by
/// being slow is not a grade.
///
/// The rungs are the Balinese *wangsa*, lowest first, and each carries a colour
/// from the grey-to-gold rarity run every player can already read without being
/// told the order. The rungs used to be the sections of a composition
/// (gineman → pekaad); those described a piece rather than a person, and a
/// section name is not something anyone wants to BE.
///
/// The names are borrowed as a familiar ORDER and nothing more. Every gloss
/// talks about the kotekan, never about the wangsa — see `gloss`, which is the
/// line that keeps this a grade rather than a claim about anybody.
///
/// A note on the bottom rung, for whoever edits this next: *paria* is not part
/// of catur wangsa — the four wangsa are Brahmana, Ksatria, Waisya and Sudra,
/// with Sudra by far the largest group in Bali. It is borrowed from the wider
/// outcaste framing, and it is the only name here that carries a slur in its
/// history. Renaming it touches this enum and nothing else; the thresholds,
/// colours and every call site key off the case, not the string.
nonisolated struct Mastery: Equatable, Sendable {
    enum Rank: Int, CaseIterable, Sendable {
        case paria, sudra, waisya, ksatria, brahmana

        /// Notes at which this rung begins.
        ///
        /// Set against what a session actually produces now that practice loops
        /// until you stop it. Ubitan Nyendok is a 2-second cycle with four polos
        /// strokes in it — two strokes a second — so twenty minutes at a decent
        /// hit rate is on the order of 1,400 landed notes. An earlier ladder was
        /// written for a scored run of eight cycles (~64 notes) and a single
        /// evening would have taken you past the top of it.
        ///
        /// Sudra lands within one solid session, so the ladder starts moving
        /// early; Brahmana is a few dozen of them.
        var threshold: Int {
            switch self {
            case .paria: return 0
            case .sudra: return 1_000
            case .waisya: return 5_000
            case .ksatria: return 15_000
            case .brahmana: return 40_000
            }
        }

        var title: String {
            switch self {
            case .paria: return "Paria"
            case .sudra: return "Sudra"
            case .waisya: return "Waisya"
            case .ksatria: return "Ksatria"
            case .brahmana: return "Brahmana"
            }
        }

        /// One line describing YOUR PLAYING — never the wangsa.
        ///
        /// This matters more than it looks. Glossing the social role ("the
        /// merchants", "the priests") had the app explaining a caste hierarchy
        /// to the person using it, and pinning the bottom of it on a beginner.
        /// Pointed at the kotekan instead, the names are just a ladder people
        /// already know the order of, and every line says something true about
        /// the player rather than something loaded about anybody else.
        ///
        /// So the rung is the label and the gloss is the skill, and the two are
        /// deliberately about different things. Keep it that way.
        var gloss: String {
            switch self {
            case .paria: return "finding the keys"
            case .sudra: return "the figure in the hands"
            case .waisya: return "holding your half"
            case .ksatria: return "interlocking at tempo"
            case .brahmana: return "the weave is yours"
            }
        }
    }

    let notes: Int
    let rank: Rank

    init(notesLanded: Int) {
        let n = max(0, notesLanded)
        notes = n
        rank = Rank.allCases.last { n >= $0.threshold } ?? .paria
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

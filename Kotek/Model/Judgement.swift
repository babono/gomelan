//
//  Judgement.swift
//  Kotek
//
//  The scoring model (PRD §5.1). Windows are deliberately generous — gamelan is
//  played at moderate tempi and beginners are slow, and the checker must err
//  generous rather than demotivate.
//

import Foundation
import SwiftUI

/// Judgement windows from §5.1. Starting values, tune during playtesting.
enum JudgementResult: String, Equatable {
    case perfect
    case good
    case lateEarly
    case miss
    case wrongKey

    var score: Int {
        switch self {
        case .perfect: return 100
        case .good: return 70
        case .lateEarly: return 30
        case .miss, .wrongKey: return 0
        }
    }

    var label: String {
        switch self {
        case .perfect: return "Perfect"
        case .good: return "Good"
        case .lateEarly: return "Late"
        case .miss: return "Miss"
        case .wrongKey: return "Wrong key"
        }
    }

    var color: Color {
        switch self {
        case .perfect: return Theme.hit
        case .good: return Theme.hit.opacity(0.8)
        case .lateEarly: return Theme.upcoming
        case .miss: return Theme.miss
        case .wrongKey: return Theme.wrong
        }
    }

    /// Correct key and reasonably on time — counts toward "on the beat".
    var onBeat: Bool { self == .perfect || self == .good }

    /// The right bilah, at all. A LATE stroke is a hit: you found the key the
    /// figure asked for, inside its own spacing, and were behind the beat doing
    /// it. That is worth less than being on the beat and it is nothing like
    /// striking the wrong bar, which is the company it used to keep — same
    /// colour on the instrument, same colour on the score, and no credit
    /// towards the gangsa.
    ///
    /// Kept separate from `onBeat` rather than folded into it: "on the beat" is
    /// a claim about timing and stays perfect-or-good. This is a claim about
    /// whether you played the note.
    var isHit: Bool { self == .perfect || self == .good || self == .lateEarly }

    /// Classify a timing error against the spacing of the figure being played.
    ///
    /// Relative to the STROKE GAP, not a flat number of milliseconds, with the
    /// old flat numbers kept as ceilings. Both halves of that matter:
    ///
    /// The relative floor is what makes the middle grades exist at all. The
    /// bundled figures run at 250ms a slot, so a flat 200ms Perfect is ±80% of
    /// a stroke — everything that landed anywhere near the right stroke was
    /// Perfect, and `.good` and `.lateEarly` were unreachable code. Being told
    /// you are perfect when you are most of a stroke out is not encouragement,
    /// it is a broken instrument.
    ///
    /// The absolute ceiling is what keeps a sparse figure honest: a rest of
    /// four slots makes a 1000ms gap, and 45% of that would call a stroke
    /// nearly half a second late "perfect".
    ///
    /// It also tracks the tempo control for free — `strokeGapMs` is measured in
    /// scaled time, so slowing a figure down widens the windows with it, which
    /// is what slowing down is for.
    static func from(timingErrorMs: Double, strokeGapMs: Double) -> JudgementResult {
        let e = abs(timingErrorMs)
        let gap = max(60, strokeGapMs)
        if e <= min(gap * 0.45, 200) { return .perfect }
        if e <= min(gap * 0.70, 350) { return .good }
        if e <= min(gap * 1.00, 500) { return .lateEarly }
        return .miss
    }
}

struct NoteJudgement: Identifiable, Equatable {
    let id = UUID()
    let keyIndex: Int
    let result: JudgementResult
    /// Signed timing error in ms; positive = struck early, negative = late.
    let timingErrorMs: Double
}

/// How one key fared across the run — drives the "where it slipped" list.
struct KeyBreakdown: Identifiable, Equatable {
    let keyIndex: Int
    let accuracy: Double   // 0…1
    let note: String       // short human description
    var id: Int { keyIndex }
}

/// One completed pass of the figure, scored on its own.
///
/// The unit everything on the results screen is built from. Practice loops
/// indefinitely now, so "the session" has no length worth averaging over — the
/// pass does.
struct CycleScore: Equatable, Identifiable {
    let index: Int
    /// When this pass began, measured from the start of the session — the
    /// results graph's x axis.
    let startMs: Double
    /// Strokes your half had this pass. Zero-note passes are possible if the
    /// player switches sides mid-cycle, and they must not divide.
    let noteCount: Int
    let score: Int
    let onBeat: Int
    let mistakes: Int

    var accuracy: Double {
        guard noteCount > 0 else { return 0 }
        return Double(score) / Double(noteCount * 100)
    }

    var id: Int { index }
}

/// The stretch of consecutive passes the headline score is taken from.
struct ScoringWindow: Equatable {
    let range: ClosedRange<Int>
    let accuracy: Double
    let onBeat: Int
    let mistakes: Int
}

struct SongResult: Equatable {
    let songTitle: String
    let subtitle: String
    /// Every note of the half you FINISHED on. Drives the per-key breakdown,
    /// which would average a bilah you play well in polos against the same
    /// bilah in sangsih if it spanned both.
    let judgements: [NoteJudgement]
    /// Every completed pass of the half you finished on, in order.
    let cycles: [CycleScore]
    /// Notes that landed across the WHOLE session, both halves — what the
    /// gangsa's grade is credited with.
    ///
    /// Separate from `judgements` on purpose: accuracy is a claim about how well
    /// you played one half and has to be scoped to it, but the grade measures
    /// how much you have played this instrument, and strokes on the other side
    /// of the kotekan are just as much playing. Switching sides costs you the
    /// accuracy history for the half you left; it never costs you the notes.
    let landedNotes: Int

    var totalScore: Int { judgements.reduce(0) { $0 + $1.result.score } }
    var maxScore: Int { judgements.count * 100 }
    var accuracy: Double {
        guard maxScore > 0 else { return 0 }
        return Double(totalScore) / Double(maxScore)
    }

    var perfectCount: Int { judgements.filter { $0.result == .perfect }.count }
    var goodCount: Int { judgements.filter { $0.result == .good }.count }
    var missCount: Int { judgements.filter { $0.result == .miss || $0.result == .wrongKey }.count }

    /// Fraction of notes struck on the correct key and reasonably on time.
    var onBeatFraction: Double {
        guard !judgements.isEmpty else { return 0 }
        return Double(judgements.filter { $0.result.onBeat }.count) / Double(judgements.count)
    }

    /// Average signed timing error across the hits that landed (excludes misses,
    /// which have no meaningful time). Positive = ahead of the beat.
    var driftMs: Double {
        let hits = judgements.filter { $0.result != .miss && $0.result != .wrongKey }
        guard !hits.isEmpty else { return 0 }
        return hits.map(\.timingErrorMs).reduce(0, +) / Double(hits.count)
    }

    /// How many consecutive passes the headline score is measured over.
    ///
    /// There is no authentic number to use here. In performance a kotekan
    /// repeats until the kendang cues the change — four times in one reading,
    /// twenty in the next — so any fixed count is a UI decision, not a musical
    /// one. Eight is long enough that a single lucky pass cannot carry it and
    /// short enough to reach in a couple of minutes.
    static let scoringWindow = 8

    /// The BEST run of `scoringWindow` consecutive passes, not the session
    /// average.
    ///
    /// Deliberately a best. Practice loops until you stop it, so a running
    /// average can only ever fall: every warm-up pass and every stretch where
    /// you paused to look at your hands drags it down for the rest of the
    /// session, and a number that gets worse the longer you practise punishes
    /// exactly the thing this screen exists to encourage. A best answers the
    /// question people actually ask — how well can I play this — and it can
    /// still only be beaten by playing well.
    var best: ScoringWindow? { SongResult.bestWindow(in: cycles) }

    /// Free-standing so the live session can ask the same question the results
    /// screen does, from the passes it has so far. Two implementations of "your
    /// best eight" would be two chances to disagree, and the number in the top
    /// bar during play has to be the number the score reports afterwards.
    static func bestWindow(in cycles: [CycleScore]) -> ScoringWindow? {
        guard !cycles.isEmpty else { return nil }
        //R Short runs are scored over what they have rather than refused a
        //R number: three passes in, "how are those three going" is a fair
        //R question. Records are gated on a full window elsewhere.
        let width = min(scoringWindow, cycles.count)
        var bestWindow: ScoringWindow?
        for start in 0...(cycles.count - width) {
            let slice = cycles[start..<(start + width)]
            let notes = slice.reduce(0) { $0 + $1.noteCount }
            guard notes > 0 else { continue }
            let score = slice.reduce(0) { $0 + $1.score }
            let candidate = ScoringWindow(range: start...(start + width - 1),
                                          accuracy: Double(score) / Double(notes * 100),
                                          onBeat: slice.reduce(0) { $0 + $1.onBeat },
                                          mistakes: slice.reduce(0) { $0 + $1.mistakes })
            if candidate.accuracy > (bestWindow?.accuracy ?? -1) { bestWindow = candidate }
        }
        return bestWindow
    }

    /// Per-key summary, worst first — "where it slipped".
    var breakdown: [KeyBreakdown] {
        let groups = Dictionary(grouping: judgements, by: \.keyIndex)
        return groups.map { key, notes -> KeyBreakdown in
            let acc = Double(notes.reduce(0) { $0 + $1.result.score }) / Double(notes.count * 100)
            let drift = notes.map(\.timingErrorMs).reduce(0, +) / Double(notes.count)
            let hasWrong = notes.contains { $0.result == .wrongKey }
            let note: String
            if acc >= 0.9 { note = "clean throughout" }
            else if hasWrong { note = "wrong key at times" }
            else if drift < -60 { note = "ran late" }
            else if drift > 60 { note = "ran early" }
            else { note = "uneven" }
            return KeyBreakdown(keyIndex: key, accuracy: acc, note: note)
        }
        .sorted { $0.accuracy > $1.accuracy }
    }
}

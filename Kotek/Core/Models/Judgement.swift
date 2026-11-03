//
//  Judgement.swift
//  Kotek
//
//  The scoring model (PRD §5.1). Windows are deliberately generous — gamelan is
//  played at moderate tempi and beginners are slow, and the checker must err
//  generous rather than demotivate.
//

import Foundation

/// Judgement windows from §5.1. Starting values, tune during playtesting.
enum JudgementResult: String, Equatable {
    case perfect
    case good
    case lateEarly
    case miss
    case wrongKey

    var score: Int {
        switch self {
        case .perfect: 100
        case .good: 70
        case .lateEarly: 30
        case .miss, .wrongKey: 0
        }
    }

    var label: String {
        switch self {
        case .perfect: "Perfect"
        case .good: "Good"
        case .lateEarly: "Late"
        case .miss: "Miss"
        case .wrongKey: "Wrong key"
        }
    }

    /// Correct key and reasonably on time — counts toward "on the beat".
    var onBeat: Bool {
        self == .perfect || self == .good
    }

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
    var isHit: Bool {
        self == .perfect || self == .good || self == .lateEarly
    }

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
    ///
    /// `leniency` widens the two grades that count towards accuracy, and only
    /// those. The ratios are capped rather than scaled freely, because there is
    /// a floor below which this stops being a grade at all: the constants above
    /// exist BECAUSE a flat 200ms Perfect once made `.good` and `.lateEarly`
    /// unreachable code, and turning the dial to maximum would rebuild that with
    /// extra steps. The cap keeps a real, if thin, band above `good`.
    static func from(
        timingErrorMs: Double,
        strokeGapMs: Double,
        leniency: Double = 1.0
    ) -> JudgementResult {
        let e = abs(timingErrorMs)
        let gap = max(60, strokeGapMs)
        let k = max(1.0, leniency)
        // R The caps are what stop this becoming a flat grade, and their values
        // R set the useful end of the slider: 0.45k reaches 0.60 at k=1.33 and
        // R 0.70k reaches 0.90 at k=1.29, so the control is live across its whole
        // R 1.0–1.3 range and saturates exactly where it runs out. Picked in that
        // R order — cap first, then range — because the first attempt had the
        // R caps biting at 1.22 against a slider that went to 1.6, so the top
        // R third of the travel moved nothing.
        let perfectRatio = min(0.45 * k, 0.60)
        let goodRatio = min(0.70 * k, 0.90)
        if e <= min(gap * perfectRatio, 200 * k) { return .perfect }
        if e <= min(gap * goodRatio, 350 * k) { return .good }
        if e <= min(gap * 1.00, 500) { return .lateEarly }
        return .miss
    }
}

struct NoteJudgement: Identifiable, Equatable {
    let id = UUID()
    let keyIndex: Int
    /// Which stroke of the figure this was: its index in ONE cycle of the half,
    /// the same number on every pass. What lets the results average "the fifth
    /// stroke" over a whole session instead of only scoring passes end to end.
    let stroke: Int
    let result: JudgementResult
    /// Signed timing error in ms; positive = struck early, negative = late.
    let timingErrorMs: Double
}

/// How one key fared across the run — drives the "where it slipped" list.
struct KeyBreakdown: Identifiable, Equatable {
    let keyIndex: Int
    let accuracy: Double // 0…1
    let note: String // short human description
    var id: Int {
        keyIndex
    }
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

    var id: Int {
        index
    }
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
    /// The OTHER half's notes at the same speed, if the player switched over to
    /// it at some point this session; empty if they never did.
    ///
    /// Kept apart from `judgements` for the reason above — everything that
    /// scores still reads only the half you finished on. This exists for the
    /// results graph, which draws the whole interlocking figure and wants to
    /// mark slips on both sides of it, not dim half of it as unplayed.
    var partnerJudgements: [NoteJudgement] = []
    /// Every completed pass of the half you finished on, in order.
    let cycles: [CycleScore]
    /// One cycle of the half you finished on, in time order — what `stroke` on
    /// a judgement indexes into — and that cycle's length. Unscaled by tempo,
    /// so a position in the cycle means the same thing at any speed.
    let strokes: [Note]
    let cycleMs: Int
    /// Notes that landed across the WHOLE session, both halves — what the
    /// gangsa's landed-note total is credited with.
    ///
    /// Separate from `judgements` on purpose: accuracy is a claim about how well
    /// you played one half and has to be scoped to it, but the total measures
    /// how much you have played this instrument, and strokes on the other side
    /// of the kotekan are just as much playing. Switching sides costs you the
    /// accuracy history for the half you left; it never costs you the notes.
    let landedNotes: Int
    /// How long the session was played, pauses and count-in left out.
    var practiceSeconds: Double = 0
    /// Whole passes played, judged or not — `cycles` holds only the judged ones.
    var passes = 0
    /// The fastest speed reached, as a tempo scale.
    var topTempoScale = 1.0
    /// Whether any stroke was judged at all. False is a session with no
    /// sensor: nothing to score, only passes, time and tempo to show.
    var sensed = true

    var totalScore: Int {
        judgements.reduce(0) { $0 + $1.result.score }
    }

    var maxScore: Int {
        judgements.count * 100
    }

    var accuracy: Double {
        guard maxScore > 0 else { return 0 }
        return Double(totalScore) / Double(maxScore)
    }

    var perfectCount: Int {
        judgements.filter { $0.result == .perfect }.count
    }

    var goodCount: Int {
        judgements.filter { $0.result == .good }.count
    }

    /// The three counts the results screen shows and `practice_session` files
    /// (`on_time_count`, `wrong_key_count`, `missed_count`) — one definition,
    /// so the screen and the database can never disagree. Whole session, not
    /// the best window: a slip outside the best eight still happened.
    var onBeatCount: Int {
        judgements.filter(\.result.onBeat).count
    }

    var wrongKeyCount: Int {
        judgements.filter { $0.result == .wrongKey }.count
    }

    var missedCount: Int {
        judgements.filter { $0.result == .miss }.count
    }

    /// Fraction of notes struck on the correct key and reasonably on time.
    var onBeatFraction: Double {
        guard !judgements.isEmpty else { return 0 }
        return Double(judgements.filter(\.result.onBeat).count) / Double(judgements.count)
    }

    /// Average signed timing error across the hits that landed (excludes misses,
    /// which have no meaningful time). Positive = ahead of the beat.
    var driftMs: Double {
        let hits = judgements.filter { $0.result != .miss && $0.result != .wrongKey }
        guard !hits.isEmpty else { return 0 }
        return hits.map(\.timingErrorMs).reduce(0, +) / Double(hits.count)
    }

    /// How each stroke of the figure went, averaged over the whole session.
    ///
    /// Replaces a pass-by-pass accuracy line, which answered "did I get better
    /// as I went" — a question practice that loops until you stop it answers
    /// itself. This answers the one a player can act on: WHERE in the figure it
    /// keeps going wrong. Strokes never judged (a pass cut short) are left out
    /// rather than read as zero.
    var strokeAverages: [StrokeAverage] {
        let byStroke = Dictionary(grouping: judgements, by: \.stroke)
        return strokes.indices.compactMap { i in
            guard let js = byStroke[i], !js.isEmpty else { return nil }
            let hits = js.filter(\.result.isHit)
            return StrokeAverage(
                stroke: i,
                keyIndex: strokes[i].keyIndex,
                timeMs: strokes[i].timeMs,
                played: js.count,
                accuracy: Double(js.reduce(0) { $0 + $1.result.score }) / Double(js.count * 100),
                driftMs: hits.isEmpty ? nil : hits.map(\.timingErrorMs).reduce(0, +) / Double(hits.count),
                misses: js.filter { $0.result == .miss }.count,
                wrongKeys: js.filter { $0.result == .wrongKey }.count
            )
        }
    }

    /// The same averages pooled into quarters of the gong cycle — the coarse
    /// "where" a person can hold in their head, and what the AI overview is
    /// told about. Quarters with no strokes in them (a sparse figure) are
    /// left out.
    var partAverages: [CyclePartAverage] {
        guard cycleMs > 0 else { return [] }
        let byPart = Dictionary(grouping: strokeAverages) { s in
            min(CyclePart.allCases.count - 1, s.timeMs * CyclePart.allCases.count / cycleMs)
        }
        return CyclePart.allCases.compactMap { part in
            guard let ss = byPart[part.rawValue], !ss.isEmpty else { return nil }
            // R Weighted by how often each stroke was judged, so a stroke that
            // R only came round once does not count as much as one that came
            // R round forty times.
            let played = ss.reduce(0) { $0 + $1.played }
            let acc = ss.reduce(0) { $0 + $1.accuracy * Double($1.played) } / Double(played)
            return CyclePartAverage(part: part, accuracy: acc, strokes: ss.map(\.stroke))
        }
    }

    /// The quarter with the lowest average, if the gap to the best one is
    /// worth pointing at. Under five points apart, every quarter went about
    /// the same, and naming one as "weakest" would invent a problem.
    var weakestPart: CyclePartAverage? {
        let parts = partAverages
        guard let low = parts.min(by: { $0.accuracy < $1.accuracy }),
              let high = parts.max(by: { $0.accuracy < $1.accuracy }),
              high.accuracy - low.accuracy >= 0.05
        else { return nil }
        return low
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
    var best: ScoringWindow? {
        SongResult.bestWindow(in: cycles)
    }

    /// Free-standing so the live session can ask the same question the results
    /// screen does, from the passes it has so far. Two implementations of "your
    /// best eight" would be two chances to disagree, and the number in the top
    /// bar during play has to be the number the score reports afterwards.
    static func bestWindow(in cycles: [CycleScore]) -> ScoringWindow? {
        guard !cycles.isEmpty else { return nil }
        // R Short runs are scored over what they have rather than refused a
        // R number: three passes in, "how are those three going" is a fair
        // R question. Records are gated on a full window elsewhere.
        let width = min(scoringWindow, cycles.count)
        var bestWindow: ScoringWindow?
        for start in 0 ... (cycles.count - width) {
            let slice = cycles[start ..< (start + width)]
            let notes = slice.reduce(0) { $0 + $1.noteCount }
            guard notes > 0 else { continue }
            let score = slice.reduce(0) { $0 + $1.score }
            let candidate = ScoringWindow(
                range: start ... (start + width - 1),
                accuracy: Double(score) / Double(notes * 100),
                onBeat: slice.reduce(0) { $0 + $1.onBeat },
                mistakes: slice.reduce(0) { $0 + $1.mistakes }
            )
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
            let note = if acc >= 0.9 {
                "clean throughout"
            } else if hasWrong {
                "wrong key at times"
            } else if drift < -60 {
                "ran late"
            } else if drift > 60 {
                "ran early"
            } else {
                "uneven"
            }
            return KeyBreakdown(keyIndex: key, accuracy: acc, note: note)
        }
        .sorted { $0.accuracy > $1.accuracy }
    }
}

/// One stroke of the figure, averaged over every pass it was judged on.
struct StrokeAverage: Identifiable, Equatable {
    let stroke: Int
    let keyIndex: Int
    /// Where it falls in the cycle, unscaled — the chart's x axis.
    let timeMs: Int
    /// How many times it was judged.
    let played: Int
    let accuracy: Double // 0…1
    /// Mean signed timing error of the strokes that landed; positive = early.
    let driftMs: Double?
    let misses: Int
    let wrongKeys: Int

    var id: Int {
        stroke
    }
}

/// A quarter of the gong cycle.
enum CyclePart: Int, CaseIterable {
    case opening, second, third, closing

    /// Short, for under the chart.
    var label: String {
        switch self {
        case .opening: "Opening"
        case .second: "Second"
        case .third: "Third"
        case .closing: "Closing"
        }
    }

    /// In a sentence — "you lose it in the closing quarter".
    var phrase: String {
        switch self {
        case .opening: "the opening quarter"
        case .second: "the second quarter"
        case .third: "the third quarter"
        case .closing: "the closing quarter, into the gong"
        }
    }
}

struct CyclePartAverage: Equatable {
    let part: CyclePart
    let accuracy: Double
    let strokes: [Int]
}

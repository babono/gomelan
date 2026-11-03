//
//  PolishSpot.swift
//  Kotek
//
//  One place in the figure that kept going wrong, and how — what "Where to
//  polish" draws and Kipli explains.
//
//  Per STROKE, folded over every pass, like the graph this replaced: the same
//  stroke slipping every time round is something you can drill, and a slip
//  that happened once in twelve passes is not worth a card. The quarters of
//  the cycle (`partAverages`) stay with the AI overview; a player looking at
//  the roll wants a bilah, not a quarter.
//

import Foundation

struct PolishSpot: Identifiable, Equatable {
    enum Kind: Equatable {
        /// A hit, just behind the beat — dragging.
        case late
        /// A hit, just ahead of it — rushing.
        case early
        /// On time, on the wrong bar: the bilah that was struck instead.
        case wrongBilah(struck: Int)
        case missed
    }

    /// The stroke's index in one cycle of the half — `SongResult.strokes`.
    let stroke: Int
    /// The bilah the figure asks for here.
    let keyIndex: Int
    let kind: Kind
    /// How many passes it went this way, out of how many it was judged.
    let times: Int
    let of: Int

    var id: Int {
        stroke
    }

    /// Bilah are numbered from 1 on screen, as on the roll.
    var title: String {
        let bilah = keyIndex + 1
        return switch kind {
        case .late: String(localized: "Bilah \(bilah) came a little late")
        case .early: String(localized: "Bilah \(bilah) came a little early")
        case let .wrongBilah(struck): String(localized: "Bilah \(struck + 1) instead of bilah \(bilah)")
        case .missed: String(localized: "Bilah \(bilah) slipped by")
        }
    }

    /// How often, then what to do about it. Two sentences, two literals: "every
    /// cycle" is a different sentence from "in 3 of 4 cycles", not a plural.
    var body: String {
        let every = times == of
        let lead = switch kind {
        case .late: every
            ? String(localized: "Every cycle, you hit it just after the beat.")
            : String(localized: "In \(times) of \(of) cycles you hit it just after the beat.")
        case .early: every
            ? String(localized: "Every cycle, you hit it just before the beat.")
            : String(localized: "In \(times) of \(of) cycles you hit it just before the beat.")
        case .wrongBilah: every
            ? String(localized: "Every cycle, your panggul landed on the bar next door.")
            : String(localized: "In \(times) of \(of) cycles your panggul landed on the bar next door.")
        case .missed: every
            ? String(localized: "Every cycle, this stroke didn't sound.")
            : String(localized: "In \(times) of \(of) cycles this stroke didn't sound.")
        }
        let advice = switch kind {
        case .late: String(localized: "Watch it slide back to where it belongs, then try landing it right on the beat.")
        case .early: String(localized: "Watch it slide forward to where it belongs, then try waiting for the beat.")
        case .wrongBilah: String(localized: "Watch it move to the right bar, then try that stroke slowly on its own.")
        case .missed: String(localized: "Play just this beat a few times, then join it back into the pattern.")
        }
        return "\(lead) \(advice)"
    }

    /// What went wrong most often, at most `limit` strokes, in the order they
    /// come in the cycle so the numbers read left to right.
    ///
    /// A late or early stroke is one graded `.lateEarly`, never `.good`: a
    /// `.good` was close enough to count as on the beat, and pointing at it
    /// would contradict the accuracy beside it.
    static func spots(in result: SongResult, limit: Int = 3) -> [PolishSpot] {
        let byStroke = Dictionary(grouping: result.judgements, by: \.stroke)
        let found: [PolishSpot] = byStroke.compactMap { stroke, js in
            guard result.strokes.indices.contains(stroke) else { return nil }
            let wrong = js.filter { $0.result == .wrongKey }
            let missed = js.count { $0.result == .miss }
            // Positive `timingErrorMs` is EARLY.
            let late = js.count { $0.result == .lateEarly && $0.timingErrorMs < 0 }
            let early = js.count { $0.result == .lateEarly && $0.timingErrorMs > 0 }
            // Ties go to the more concrete slip: a wrong bar, then a missing one.
            var best: (kind: Kind, times: Int)?
            if let struck = Dictionary(grouping: wrong, by: \.keyIndex).max(by: { $0.value.count < $1.value.count })?
                .key
            {
                best = (.wrongBilah(struck: struck), wrong.count)
            }
            for (kind, n) in [(Kind.missed, missed), (.late, late), (.early, early)] where n > (best?.times ?? 0) {
                best = (kind, n)
            }
            guard let best else { return nil }
            return PolishSpot(
                stroke: stroke,
                keyIndex: result.strokes[stroke].keyIndex,
                kind: best.kind,
                times: best.times,
                of: js.count
            )
        }
        return found
            .sorted { ($0.times, $1.stroke) > ($1.times, $0.stroke) }
            .prefix(limit)
            .sorted { $0.stroke < $1.stroke }
    }

    #if DEBUG
        /// Three strokes over two passes: 0 clean, 1 late twice, 2 struck on
        /// bilah 5 once and missed once — the wrong bar wins the tie.
        static func selfCheck() {
            let strokes = (0 ..< 3).map { Note(keyIndex: $0, timeMs: $0 * 250, durationMs: 200) }
            let j: [NoteJudgement] = (0 ..< 2).flatMap { pass in
                [
                    NoteJudgement(keyIndex: 0, stroke: 0, result: .perfect, timingErrorMs: 0),
                    NoteJudgement(keyIndex: 1, stroke: 1, result: .lateEarly, timingErrorMs: -120),
                    pass == 0
                        ? NoteJudgement(keyIndex: 4, stroke: 2, result: .wrongKey, timingErrorMs: 0)
                        : NoteJudgement(keyIndex: 2, stroke: 2, result: .miss, timingErrorMs: 0)
                ]
            }
            let r = SongResult(
                songTitle: "", subtitle: "", judgements: j, cycles: [],
                strokes: strokes, cycleMs: 750, landedNotes: 0
            )
            let s = spots(in: r)
            assert(s.map(\.stroke) == [1, 2])
            assert(s[0].kind == .late && s[0].times == 2 && s[0].of == 2)
            assert(s[1].kind == .wrongBilah(struck: 4) && s[1].times == 1)
        }
    #endif
}

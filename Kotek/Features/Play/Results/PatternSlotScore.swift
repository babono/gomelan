//
//  PatternSlotScore.swift
//  Kotek
//
//  How each position of the figure fared, folded across every pass.
//
//  The graph used to run over passes — accuracy per cycle — which answers "did
//  I get better as I went" and nothing else. What a player can actually act on
//  is WHERE in the kotekan it goes wrong: the same stroke failing every time
//  round is a figure problem you can drill, and a per-cycle line averages it
//  away into a slightly lower number.
//

import Foundation

struct PatternSlotScore: Identifiable, Equatable {
    /// Which side of the kotekan — the graph draws both, interlocked.
    let half: KotekanHalf
    /// Grid slot in the cycle, 0 ..< slotsPerCycle.
    let slot: Int
    /// The bilah the figure asks for here, nil on a rest.
    let keyIndex: Int?
    /// Times this stroke came round and was judged.
    let attempts: Int
    let wrongKey: Int
    let missed: Int

    var id: String {
        "\(half.rawValue)-\(slot)"
    }

    var slips: Int {
        wrongKey + missed
    }

    /// Fraction of attempts that were a wrong bar or a miss, 0…1.
    var slipRate: Double {
        attempts > 0 ? Double(slips) / Double(attempts) : 0
    }

    /// One entry per grid slot of `pattern` — rests included, so the graph
    /// keeps the figure's real spacing and the off-beat gaps stay visible.
    ///
    /// A judgement's `stroke` counts strokes only, rests skipped, the way
    /// `makeSong` lays them out — so the n-th struck slot of the grid is
    /// stroke n.
    static func fold(_ judgements: [NoteJudgement], over pattern: [Int?], half: KotekanHalf) -> [PatternSlotScore] {
        let byStroke = Dictionary(grouping: judgements, by: \.stroke)
        var stroke = 0
        return pattern.enumerated().map { slot, key in
            var notes: [NoteJudgement] = []
            if key != nil {
                notes = byStroke[stroke] ?? []
                stroke += 1
            }
            return PatternSlotScore(
                half: half,
                slot: slot,
                keyIndex: key,
                attempts: notes.count,
                wrongKey: notes.filter { $0.result == .wrongKey }.count,
                missed: notes.filter { $0.result == .miss }.count
            )
        }
    }

    /// The strokes that slipped most, worst first. Ties go to the earlier slot
    /// so the order is stable from one look to the next.
    static func worst(_ slots: [PatternSlotScore], limit: Int = 3) -> [PatternSlotScore] {
        slots
            .filter { $0.slips > 0 }
            .sorted { ($0.slipRate, -$0.slot) > ($1.slipRate, -$1.slot) }
            .prefix(limit)
            .map { $0 }
    }
}

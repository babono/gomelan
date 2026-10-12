//
//  SessionFacts.swift
//  Kotek
//
//  What the AI overview is told about a session, written out as plain
//  sentences before the model ever sees it.
//
//  The arithmetic happens HERE, not in the model. A small on-device model asked
//  to read raw judgements will happily average them wrong, or call 53% "your
//  strongest"; given the conclusions as text, its only job is to say them
//  kindly and pick advice — which is the part it is good at.
//

import Foundation

nonisolated struct SessionFacts: Sendable, Equatable {
    /// The facts, one per line, as the model reads them.
    let text: String
    /// What the book is searched with: the problem, in the words a teaching
    /// text would use for it, rather than the numbers.
    let query: String
}

extension SessionFacts {
    /// Average timing within this of the beat is "on time" — closer than
    /// anyone can hear, and not worth an overview's sentence.
    private static let driftWorthMentioningMs = 25.0

    init(result: SongResult, figure: String, half: String, tempo: String) {
        var lines: [String] = []
        lines.append("Figure: \(figure), playing the \(half) half, at \(tempo) speed.")
        lines.append("Full cycles played: \(result.cycles.count).")
        if let best = result.best {
            lines.append("Best accuracy over \(best.range.count) cycles in a row: \(Self.percent(best.accuracy)).")
        }

        let parts = result.partAverages
        if !parts.isEmpty {
            let list = parts.map { "\($0.part.label.lowercased()) \(Self.percent($0.accuracy))" }
            lines.append("Average accuracy in each quarter of the gong cycle: \(list.joined(separator: ", ")).")
        }

        let strokes = result.strokeAverages
        var problems: [String] = []
        if let weakest = result.weakestPart {
            let inPart = strokes.filter { weakest.strokes.contains($0.stroke) }
            let misses = inPart.reduce(0) { $0 + $1.misses }
            let wrong = inPart.reduce(0) { $0 + $1.wrongKeys }
            var line = "Weakest: \(weakest.part.phrase), at \(Self.percent(weakest.accuracy))."
            if misses > 0 { line += " Strokes missed there: \(misses)." }
            if wrong > 0 { line += " Wrong bilah struck there: \(wrong)." }
            if let drift = Self.drift(of: inPart) { line += " Strokes there land \(drift)." }
            lines.append(line)
            problems.append("losing the pattern in \(weakest.part.phrase)")
            if misses > wrong { problems.append("dropping strokes") }
            if wrong > 0 { problems.append("striking the wrong key") }
        } else if !parts.isEmpty {
            lines.append("Every quarter of the cycle is within a few points of the others.")
        }

        if let drift = Self.drift(of: strokes) {
            lines.append("Across the whole figure, strokes land \(drift).")
            problems.append(drift.contains("early") ? "rushing ahead of the beat" : "dragging behind the beat")
        }

        if problems.isEmpty { problems.append("playing steadily at a faster tempo") }
        text = lines.joined(separator: "\n")
        // R In the BOOK's words, not a learner's. A text about gamelan says
        // R "kotekan", "polos", "sangsih", "gong cycle"; it rarely says "how to
        // R practise", and a query phrased that way matched drum technique.
        query = "Kotekan polos and sangsih interlocking on the gangsa, playing the \(half): \(problems.joined(separator: ", ")), in the gong cycle."
    }

    private static func percent(_ x: Double) -> String {
        "\(Int((x * 100).rounded()))%"
    }

    /// "40 ms late on average", or nil if it is close enough to on time.
    /// Weighted by how often each stroke landed.
    private static func drift(of strokes: [StrokeAverage]) -> String? {
        var total = 0.0, n = 0
        for s in strokes {
            guard let d = s.driftMs else { continue }
            let landed = s.played - s.misses - s.wrongKeys
            total += d * Double(landed)
            n += landed
        }
        guard n > 0 else { return nil }
        let mean = total / Double(n)
        guard abs(mean) >= driftWorthMentioningMs else { return nil }
        // R Positive is EARLY — `timingErrorMs` is due time minus strike time.
        return "\(Int(abs(mean).rounded())) ms \(mean > 0 ? "early" : "late") on average"
    }
}

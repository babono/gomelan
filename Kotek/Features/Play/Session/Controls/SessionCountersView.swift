//
//  SessionCountersView.swift
//  Kotek
//
//  "Cycle 12 · 148 · 86% / 94%" — how far round, how much of it counted, and
//  how close you are to beating this figure.
//

import SwiftUI

struct SessionCountersView: View {
    let engine: PlayEngine
    /// The best this figure has ever been played on this gangsa, at this half
    /// and speed. nil until eight consecutive cycles have been played once.
    let record: Double?

    private var beatingRecord: Bool {
        guard let record, let best = engine.bestSoFar else { return false }
        return best >= record
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(
                engine.phase == .countIn
                    ? "Count-in" : "Cycle \(engine.loopIndex + 1)"
            )
            .foregroundStyle(Theme.inkStone)

            if engine.landedNotes > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.symbol(11, weight: .bold))
                    Text("\(engine.landedNotes)")
                }
                .foregroundStyle(Theme.hit)
                .accessibilityLabel("\(engine.landedNotes) notes landed")
            }

            // Always drawn, even before a single pass has closed.
            HStack(spacing: 3) {
                Text(engine.bestSoFar.map(percent) ?? "—")
                    .foregroundStyle(beatingRecord ? Theme.hit : Theme.cream)
                if let record {
                    Text("/").foregroundStyle(Theme.inkStone.opacity(0.6))
                    Text(percent(record)).foregroundStyle(Theme.gold)
                }
            }
            .coachTarget(.score)
            .accessibilityLabel(accessibilityLabel)
        }
        .font(.sans(14))
        .contentTransition(.numericText())
        .animation(.snappy(duration: 0.25), value: engine.landedNotes)
        .animation(.snappy(duration: 0.25), value: engine.bestSoFar)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        parts.append(
            engine.bestSoFar.map { "best so far \(percent($0))" }
                ?? "no score yet"
        )
        if let record { parts.append("record \(percent(record))") }
        if beatingRecord { parts.append("beating the record") }
        return parts.joined(separator: ", ")
    }
}

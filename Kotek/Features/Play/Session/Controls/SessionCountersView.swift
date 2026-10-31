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

            // Guidance only (no sensor): the cycle count is all there is.
            if engine.judging, engine.landedNotes > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.symbol(11, weight: .bold))
                    Text("\(engine.landedNotes)")
                }
                .foregroundStyle(Theme.hit)
                .accessibilityLabel("\(engine.landedNotes) notes landed")
            }

            // Always drawn, even before a single pass has closed.
            if engine.judging {
                HStack(spacing: 3) {
                    Text(engine.bestSoFar.map(Theme.percentLabel) ?? "—")
                        .foregroundStyle(beatingRecord ? Theme.hit : Theme.cream)
                    if let record {
                        Text("/").foregroundStyle(Theme.inkStone.opacity(0.6))
                        Text(Theme.percentLabel(record)).foregroundStyle(Theme.gold)
                    }
                }
                .coachTarget(.score)
                .accessibilityLabel(accessibilityLabel)
            }
        }
        .font(.sans(14))
        .contentTransition(.numericText())
        .animation(.snappy(duration: 0.25), value: engine.landedNotes)
        .animation(.snappy(duration: 0.25), value: engine.bestSoFar)
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        parts.append(
            engine.bestSoFar.map { String(localized: "best so far \(Theme.percentLabel($0))") }
                ?? String(localized: "no score yet")
        )
        if let record { parts.append(String(localized: "record \(Theme.percentLabel(record))")) }
        if beatingRecord { parts.append(String(localized: "beating the record")) }
        return parts.joined(separator: ", ")
    }
}

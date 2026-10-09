//
//  ResultsView.swift
//  Kotek
//
//  The score, shown only when the player ends a session (PRD §4 Flow C, §8).
//  Practice loops indefinitely and never interrupts, so this is the one moment
//  the app says anything about how it went — encouraging tone with best stretch.
//

import SwiftUI

struct ResultsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if let result = app.lastResult {
            VStack(spacing: 0) {
                header(result)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 16) {
                        if let best = result.best {
                            HStack(alignment: .top, spacing: 28) {
                                ResultsHeadlineView(best: best, result: result)
                                performance(result, best: best)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            tooShort
                        }

                        // Always, even after a session too short to score: the
                        // notes still landed and the gangsa still learned them.
                        MasteryProgressView(
                            profile: app.profile,
                            before: app.previousNotesLanded,
                            landed: result.landedNotes
                        )

                        ResultsBottomBar(
                            onChooseAnother: { app.backToKotekan() },
                            onRetry: { app.retry() }
                        )
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                }
            }
        } else {
            Color.clear.onAppear { app.backToKotekan() }
        }
    }

    private func header(_ result: SongResult) -> some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel("Result", color: Theme.stone)
                Spacer()
                Text(result.subtitle)
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(Theme.terracotta)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 10)
            Rectangle().fill(Theme.charcoal.opacity(0.12)).frame(height: 1)
        }
    }

    /// Accuracy pass by pass, with the stretch the headline came from lit.
    private func performance(_ result: SongResult, best: ScoringWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Performance", color: Theme.stone)

            PerformanceGraph(cycles: result.cycles, best: best.range)
                .frame(height: 108)
                .frame(maxWidth: .infinity)

            HStack {
                Text("\(result.cycles.count) cycle\(result.cycles.count == 1 ? "" : "s")")
                Spacer()
                Text("best \(best.range.lowerBound + 1)–\(best.range.upperBound + 1)")
                    .foregroundStyle(Theme.terracotta)
            }
            .font(.sans(12))
            .foregroundStyle(Theme.stone)
        }
    }

    /// Ended before a single pass came round.
    private var tooShort: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Not enough to score")
                .font(.serif(34))
                .foregroundStyle(Theme.charcoal)
            Text(
                "The figure has to come round at least once. Give it a full pass of the gong cycle and the score has something to measure."
            )
            .font(.sans(15))
            .foregroundStyle(Theme.stone)
            .lineSpacing(3)
            .frame(maxWidth: 460, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

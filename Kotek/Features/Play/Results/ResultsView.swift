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
    @State private var overview = SessionOverviewModel()

    var body: some View {
        if let result = app.lastResult {
            VStack(spacing: 0) {
                header(result)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 16) {
                        if let best = result.best {
                            HStack(alignment: .top, spacing: 28) {
                                ResultsHeadlineView(best: best, result: result)
                                performance(result)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            SessionOverviewCard(model: overview)
                                .task { await overview.run(facts: facts(for: result)) }
                        } else {
                            tooShort
                        }

                        ResultsBottomBar(
                            onChooseAnother: { app.backToKotekan() },
                            onRetry: { app.retry() }
                        )
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                }
            }
            .overlay {
                if app.showingSavePrompt {
                    SaveProgressPrompt()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: app.showingSavePrompt)
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

    private func facts(for result: SongResult) -> SessionFacts {
        SessionFacts(
            result: result,
            figure: app.selectedKotekan?.name ?? result.songTitle,
            half: app.chosenHalf.title.lowercased(),
            tempo: Theme.tempoLabel(app.tempoScale)
        )
    }

    /// Where in the figure it went right and wrong, averaged over the session.
    private func performance(_ result: SongResult) -> some View {
        let weakest = result.weakestPart
        return VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Across the cycle", color: Theme.stone)

            CycleAccuracyChart(
                strokes: result.strokeAverages,
                parts: result.partAverages,
                cycleMs: result.cycleMs,
                weakest: weakest?.part
            )
            .frame(height: 120)
            .frame(maxWidth: .infinity)

            HStack {
                Text("average of \(result.cycles.count) cycle\(result.cycles.count == 1 ? "" : "s")")
                Spacer()
                if let weakest {
                    Text("work on the \(weakest.part.label.lowercased()) quarter")
                        .foregroundStyle(Theme.miss)
                } else {
                    Text("even all the way round")
                        .foregroundStyle(Theme.terracotta)
                }
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
                "The pattern has to come round at least once. Give it a full pass of the gong cycle and the score has something to measure."
            )
            .font(.sans(15))
            .foregroundStyle(Theme.stone)
            .lineSpacing(3)
            .frame(maxWidth: 460, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

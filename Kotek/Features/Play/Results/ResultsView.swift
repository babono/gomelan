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

                // R No outer scroll. Graph, counts, feedback and the buttons
                // R were stacked in one ScrollView, and on a landscape phone the
                // R feedback and Retry sat below the fold — the screen whose job
                // R is "what next" hid the what-next. Now the graph takes the
                // R left and everything you read or tap after it is on the right.
                HStack(alignment: .top, spacing: 32) {
                    Group {
                        if result.best != nil {
                            performance(result)
                        } else {
                            tooShort
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)

                    VStack(alignment: .leading, spacing: 18) {
                        if result.best != nil {
                            ResultsHeadlineView(result: result)
                        }
                        // The only part that can outgrow the column,
                        // expanded, so the only part that scrolls. Not after
                        // a session too short to score: there is nothing for
                        // the model to read, and `tooShort` already says what
                        // to do about it.
                        ScrollView(.vertical, showsIndicators: false) {
                            if result.best != nil {
                                ResultsFeedbackView(model: overview)
                            }
                        }
                        .scrollBounceBehavior(.basedOnSize)

                        ResultsBottomBar(
                            onChooseAnother: { app.backToKotekan() },
                            onRetry: { app.retry() }
                        )
                    }
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, 40)
                .padding(.top, 14)
            }
            .overlay {
                if app.showingSavePrompt {
                    SaveProgressPrompt()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: app.showingSavePrompt)
            .task(id: result) {
                guard result.best != nil else { return }
                await overview.run(facts: facts(result))
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

    /// Both halves' slots in order, each folded over every pass of it that was
    /// played. Empty if the figure is gone — the screen then just has no graph
    /// rather than a wrong one.
    private func slots(_ result: SongResult) -> [PatternSlotScore] {
        guard let k = app.selectedKotekan else { return [] }
        let mine = app.chosenHalf
        return PatternSlotScore.fold(result.judgements, over: k.pattern(mine), half: mine)
            + PatternSlotScore.fold(result.partnerJudgements, over: k.pattern(mine.other), half: mine.other)
    }

    private func facts(_ result: SongResult) -> SessionFacts {
        SessionFacts(
            result: result,
            figure: app.selectedKotekan?.name ?? result.songTitle,
            half: app.chosenHalf.title.lowercased(),
            tempo: Theme.tempoLabel(app.tempoScale)
        )
    }

    /// The figure as a piano roll, both halves, with where it went wrong
    /// marked on it — every pass folded onto one.
    private func performance(_ result: SongResult) -> some View {
        let slots = slots(result)
        let worst = PatternSlotScore.worst(slots, limit: 1).first
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Performance", color: Theme.stone)

            // Takes whatever height the screen has left — no scroll to reach it.
            PerformanceGraph(slots: slots, keyCount: app.profile.keyCount, worst: worst)
                .frame(maxHeight: .infinity)

            HStack(spacing: 14) {
                legend("Polos", Theme.polosVoice)
                legend("Sangsih", Theme.sangsihVoice)
                legend("Wrong bilah", Theme.wrong)
                legend("Missed", Theme.miss)
            }
            .font(.sans(12))
            .foregroundStyle(Theme.stone)

            Group {
                if let worst {
                    Text("most slips · \(worst.half.title) on bilah \(worst.keyIndex.map { bilahLabel($0, count: app.profile.keyCount) } ?? "–")")
                        .foregroundStyle(Theme.terracotta)
                } else {
                    Text("no slips")
                        .foregroundStyle(Theme.hit)
                }
            }
            .font(.sans(12))
            .foregroundStyle(Theme.stone)
        }
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 8)
            Text(label)
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

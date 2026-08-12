//
//  ResultsView.swift
//  gomelan
//
//  Post-session score (PRD §4 Flow C, §8). The tone stays encouraging — accuracy
//  up top, then where it slipped, framed as observations rather than failures.
//

import SwiftUI

struct ResultsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if let result = app.lastResult {
            VStack(spacing: 0) {
                header(result)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 24) {
                        HStack(alignment: .top, spacing: 0) {
                            accuracyColumn(result)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Rectangle()
                                .fill(Theme.charcoal.opacity(0.15))
                                .frame(width: 1)

                            slippedColumn(result)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        bottomBar
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)
                }
            }
            .background(Theme.cream)
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
            .padding(.vertical, 16)
            Rectangle().fill(Theme.charcoal.opacity(0.12)).frame(height: 1)
        }
    }

    private func accuracyColumn(_ result: SongResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Accuracy")
            Text("\(Int((result.accuracy * 100).rounded()))%")
                .font(.serif(68))
                .foregroundStyle(Theme.charcoal)

            Rectangle().fill(Theme.charcoal.opacity(0.15))
                .frame(width: 200, height: 1)
                .padding(.vertical, 14)

            HStack(spacing: 36) {
                stat("On the beat", "\(Int((result.onBeatFraction * 100).rounded()))%")
                stat("Drift", String(format: "%+.0f ms", result.driftMs))
            }
        }
        .padding(.trailing, 28)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(label, color: Theme.stone)
            Text(value).font(.serif(28)).foregroundStyle(Theme.charcoal)
        }
    }

    private func slippedColumn(_ result: SongResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Where it slipped", color: Theme.stone)
            ForEach(result.breakdown) { row in
                HStack(spacing: 12) {
                    Text(bilahLabel(row.keyIndex, count: app.profile.keys.count))
                        .font(.serif(18, weight: .semibold))
                        .foregroundStyle(Theme.charcoal)
                        .frame(width: 26, alignment: .leading)
                    StatBar(fraction: row.accuracy,
                            color: row.accuracy >= 0.7 ? Theme.terracotta : Theme.charcoal.opacity(0.6))
                    Text(row.note)
                        .font(.sans(13))
                        .foregroundStyle(Theme.stone)
                        .frame(width: 140, alignment: .trailing)
                }
            }
        }
        .padding(.leading, 28)
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            PillButton(title: "Retry", style: .outlined, tint: Theme.terracotta) {
                app.retry()
            }
            PillButton(title: "Choose Kotekan", style: .filled, tint: Theme.terracotta) {
                app.backToKotekan()
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 16)
    }
}

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

                HStack(alignment: .top, spacing: 0) {
                    accuracyColumn(result)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Rectangle().fill(Theme.charcoal.opacity(0.15)).frame(width: 1)

                    slippedColumn(result)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 28)
                .frame(maxHeight: .infinity)

                HStack(spacing: 16) {
                    PillButton(title: "Retry", style: .outlined) { app.retry() }
                    PillButton(title: "Back to main", style: .secondary, uppercase: true) { app.backToKotekan() }
                }
                .padding(.bottom, 28)
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
            .padding(.vertical, 18)
            Rectangle().fill(Theme.charcoal.opacity(0.12)).frame(height: 1)
        }
    }

    private func accuracyColumn(_ result: SongResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Accuracy")
            Text("\(Int((result.accuracy * 100).rounded()))%")
                .font(.serif(96))
                .foregroundStyle(Theme.charcoal)

            Rectangle().fill(Theme.charcoal.opacity(0.15))
                .frame(width: 240, height: 1)
                .padding(.vertical, 18)

            HStack(spacing: 48) {
                stat("On the beat", "\(Int((result.onBeatFraction * 100).rounded()))%")
                stat("Drift", String(format: "%+.0f ms", result.driftMs))
            }
        }
        .padding(.trailing, 32)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(label, color: Theme.stone)
            Text(value).font(.serif(34)).foregroundStyle(Theme.charcoal)
        }
    }

    private func slippedColumn(_ result: SongResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLabel("Where it slipped", color: Theme.stone)
            ForEach(result.breakdown) { row in
                HStack(spacing: 16) {
                    Text(bilahLabel(row.keyIndex, count: app.profile.keys.count))
                        .font(.serif(22))
                        .foregroundStyle(Theme.charcoal)
                        .frame(width: 26, alignment: .leading)
                    StatBar(fraction: row.accuracy,
                            color: row.accuracy >= 0.7 ? Theme.terracotta : Theme.charcoal.opacity(0.6))
                    Text(row.note)
                        .font(.sans(14))
                        .foregroundStyle(Theme.stone)
                        .frame(width: 150, alignment: .trailing)
                }
            }
        }
        .padding(.leading, 32)
    }
}

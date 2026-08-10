//
//  ResultsView.swift
//  gomelan
//
//  Post-song score and retry (PRD §4 Flow C, §8). Only shown after a scored
//  Play run; Practice ends without a score by design (§5.3).
//

import SwiftUI

struct ResultsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if let result = app.lastResult {
            HStack(spacing: 48) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(result.songTitle)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("\(Int(result.accuracy * 100))%")
                        .font(.system(size: 96, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.accent)
                    Text("\(result.totalScore) / \(result.maxScore) points")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        StatPill(label: "Perfect", value: result.perfectCount, color: Theme.hit)
                        StatPill(label: "Good", value: result.goodCount, color: Theme.hit.opacity(0.7))
                        StatPill(label: "Missed", value: result.missCount, color: Theme.miss)
                    }

                    PrimaryButton(title: "Retry", systemImage: "arrow.clockwise") { app.retry() }
                    SecondaryButton(title: "Back to songs", systemImage: "list.bullet") { app.backToSongs() }

                    // An honest ending: point toward real teaching (§11 Q4).
                    Text("Enjoyed this? Find a teacher or a local sekaa — Gomelan is a first step, not a replacement.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(48)
        } else {
            Color.clear.onAppear { app.backToSongs() }
        }
    }
}

private struct StatPill: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.title2.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: 90)
        .padding(.vertical, 14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

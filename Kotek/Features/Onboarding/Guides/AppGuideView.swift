//
//  AppGuideView.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// Explainer content for "Your gangsa" (.app guide).
struct AppGuideView: View {
    var body: some View {
        GuideColumns {
            AppGuideInstrument()
        } right: {
            AppGuideGrade()
        }
    }
}

/// What the instrument on the other side of the camera is, and why it is the only one.
struct AppGuideInstrument: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideBlock(
                "The instrument",
                "Bronze bilah over bamboo resonators, struck with a panggul and damped with the other hand. Bronze rings for seconds, so damping matters as much as striking."
            )

            GuideBlock(
                "Only the gangsa",
                "Kotek reads one instrument. Reyong, jegogan, kendang and the rest of the gamelan are not supported yet."
            )

            GuideBlock(
                "Yours, specifically",
                "No two gamelan are tuned alike, so the app learns your instrument once — where its keys are, how a strike sounds — and keeps it. Each card here is one."
            )
        }
    }
}

/// The five rungs, what each is called, and what it costs in notes.
struct AppGuideGrade: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Its grade", color: Theme.gold)

            GuideLead(
                "Notes that land — right key, near enough the beat — build the grade of the gangsa you played them on. It only ever goes up."
            )

            VStack(spacing: 0) {
                ForEach(Mastery.Rank.allCases.reversed(), id: \.self) { rank in
                    row(rank)
                    if rank != Mastery.Rank.allCases.first {
                        Rectangle().fill(Theme.cream.opacity(0.07)).frame(height: 1)
                    }
                }
            }
            .padding(.vertical, 3)
            .background(
                Theme.ground.opacity(0.5),
                in: RoundedRectangle(cornerRadius: Theme.radius)
            )
        }
    }

    private func row(_ rank: Mastery.Rank) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(rank.color)
                .frame(width: 8, height: 18)

            Text(rank.title)
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(rank.color)
                .fixedSize()

            Text(rank.gloss)
                .font(.sans(11))
                .foregroundStyle(Theme.cream.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 6)

            Text(
                rank.threshold == 0
                    ? "from note one" : "\(rank.threshold.formatted())"
            )
            .font(.sans(11, weight: .medium))
            .foregroundStyle(Theme.cream.opacity(0.62))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

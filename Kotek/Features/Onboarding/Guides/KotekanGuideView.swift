//
//  KotekanGuideView.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// Explainer content for "Kotekan" (.kotekan guide).
struct KotekanGuideView: View {
    var body: some View {
        GuideColumns {
            KotekanGuideWeave()
        } right: {
            KotekanGuideLegend()
        }
    }
}

struct KotekanGuideWeave: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideBlock(
                "One melody, two players",
                "A kotekan is a line too fast to play alone, so it is split. Neither part is the tune. The tune is what you hear when both are going."
            )

            GuideBlock(
                "Polos",
                "The straight half. It lands on the beat with the kajar and holds the frame steady. This is the one to learn first."
            )

            GuideBlock(
                "Sangsih",
                "The answering half. It falls in the gaps polos leaves, off the beat — harder, and the reason the pair sounds twice as fast as either."
            )
        }
    }
}

struct KotekanGuideLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Reading a card", color: Theme.gold)

            GuideLead(
                "Each card draws its figure across one gong cycle: time runs left to right, and the keys go low to high up the side. Swipe to hear the next."
            )

            VStack(spacing: 0) {
                row(swatch: .single(Theme.polosVoice), "Polos", "on the beat")
                divider
                row(
                    swatch: .single(Theme.sangsihVoice),
                    "Sangsih",
                    "between the beats"
                )
                divider
                row(swatch: .split, "Both together", "the shared anchor tone")
                divider
                row(swatch: .line, "The sweep", "where the cycle is now")
            }
            .padding(.vertical, 3)
            .background(
                Theme.ground.opacity(0.5),
                in: RoundedRectangle(cornerRadius: Theme.radius)
            )
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.cream.opacity(0.07)).frame(height: 1)
    }

    private enum Swatch {
        case single(Color)
        case split
        case line
    }

    private func row(swatch: Swatch, _ title: String, _ gloss: String) -> some View {
        HStack(spacing: 10) {
            Group {
                switch swatch {
                case let .single(color):
                    RoundedRectangle(cornerRadius: 2).fill(color)
                case .split:
                    HStack(spacing: 0) {
                        Rectangle().fill(Theme.polosVoice)
                        Rectangle().fill(Theme.sangsihVoice)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                case .line:
                    Rectangle().fill(Theme.cream.opacity(0.85)).frame(width: 2)
                }
            }
            .frame(width: 20, height: 14)

            Text(title)
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(Theme.cream)
                .fixedSize()

            Text(gloss)
                .font(.sans(11))
                .foregroundStyle(Theme.cream.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

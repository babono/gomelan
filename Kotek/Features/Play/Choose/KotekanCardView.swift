//
//  KotekanCardView.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// A card in the Kotekan selection carousel showing title, catalog tag, mini score,
/// and mastery record or key requirement warning.
struct KotekanCardView: View {
    let kotekan: Kotekan
    let isPlaying: Bool
    let offset: Double
    let canPlay: Bool
    let engine: PlayEngine?
    let bestRecord: PatternRecord?

    static let cardWidth: CGFloat = 272
    static let cardHeight: CGFloat = 178

    var body: some View {
        let nearness: CGFloat = max(0, 1 - min(abs(CGFloat(offset)), 1.6) / 1.6)

        return cardBody
            .padding(18)
            .frame(width: Self.cardWidth, height: Self.cardHeight, alignment: .topLeading)
            .background(
                Theme.deep.opacity(0.55 + 0.3 * nearness),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        Theme.buttonFill.opacity(nearness),
                        lineWidth: 1 + nearness
                    )
            )
            .scaleEffect(0.84 + 0.16 * nearness)
            .opacity(0.35 + 0.65 * nearness)
            .allowsHitTesting(false)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(kotekan.catalogLabel, color: Theme.terracotta)

            Text(kotekan.name)
                .font(.serif(26))
                .foregroundStyle(Theme.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            KotekanMiniScore(kotekan: kotekan, engine: isPlaying ? engine : nil)
                .frame(height: 54)
                .padding(.top, 2)

            Spacer(minLength: 4)

            cardFoot
        }
    }

    @ViewBuilder
    private var cardFoot: some View {
        if !canPlay {
            Label("Needs \(kotekan.requiredKeys) keys", systemImage: "lock")
                .font(.sans(12, weight: .medium))
                .foregroundStyle(Theme.miss)
        } else if let record = bestRecord {
            HStack(spacing: 6) {
                Image(systemName: "trophy").font(.symbol(11, weight: .semibold))
                Text(String(format: "%.0f%%", record.accuracy * 100))
                    .font(.sans(13, weight: .semibold))
                Text("\(record.half.capitalized) · \(Theme.tempoLabel(record.tempo))")
                    .font(.sans(12))
                    .foregroundStyle(Theme.cream.opacity(0.45))
            }
            .foregroundStyle(Theme.terracotta)
        }
    }
}

//
//  KotekanCardView.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// A card in the Kotekan selection carousel: the title, a mini score, and its
/// tempo with the mastery record (or the key requirement) under it. The
/// centred card is the one previewing, and only it carries the mute.
struct KotekanCardView: View {
    let kotekan: Kotekan
    let isPlaying: Bool
    let canPlay: Bool
    let engine: PlayEngine?
    let bestRecord: PatternRecord?
    /// One mute for the whole picker, not per card: it is the preview's.
    @Binding var muted: Bool
    let offset: Double
    /// How small the cards beside the selected one are, from `CarouselFit` so
    /// they end at the rail's edge rather than past it.
    let sideScale: CGFloat
    /// As tall as the rail allows, up to `maxHeight`.
    let height: CGFloat

    static let cardWidth: CGFloat = 272
    /// Was 178, a strip of score under the title. With the Start footer gone
    /// the rail has the room; 240 crowded the search row.
    static let maxHeight: CGFloat = 210

    var body: some View {
        let nearness: CGFloat = max(0, 1 - min(abs(CGFloat(offset)), 1.6) / 1.6)

        return content
            .padding(16)
            .frame(width: Self.cardWidth, height: height, alignment: .topLeading)
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
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20))
            .scaleEffect(1 - (1 - sideScale) * min(abs(CGFloat(offset)), 1))
            .opacity(0.35 + 0.65 * nearness)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kotekan.name)
                .font(.serif(26))
                .foregroundStyle(Theme.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            KotekanMiniScore(kotekan: kotekan, engine: isPlaying ? engine : nil)
                .frame(maxHeight: .infinity)

            HStack(spacing: 6) {
                cardFoot
                Spacer(minLength: 0)
                if isPlaying {
                    AppIconButton(
                        systemImage: muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        label: muted ? "Unmute the preview" : "Mute the preview",
                        size: .compact
                    ) {
                        muted.toggle()
                    }
                }
            }
            // The row keeps the speaker's height on every card, so the
            // scores line up whether or not it is showing.
            .frame(height: AppButtonSize.compact.height)
        }
    }

    @ViewBuilder
    private var cardFoot: some View {
        if !canPlay {
            Label("Needs \(kotekan.requiredKeys) keys", systemImage: "lock")
                .font(.sans(12, weight: .medium))
                .foregroundStyle(Theme.miss)
        } else {
            // Nothing is scored without the sensor, so the record is only
            // shown when the caller has one to beat.
            Text(bestRecord.map { "\(kotekan.bpm) BPM · best \(String(format: "%.0f%%", $0.accuracy * 100))" }
                ?? "\(kotekan.bpm) BPM")
                .font(.sans(13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.terracotta)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

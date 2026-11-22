//
//  KotekanCardView.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// A card in the Kotekan selection carousel: the title, a mini score, and its
/// length and tempo with the mastery record (or the key requirement) under it. The
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
        // 0 on the centred card, 1 from one card away.
        let away = min(abs(CGFloat(offset)), 1)

        // The centred card is the selected one: gold, edged, tumpal — see
        // `pickerCard`. The rest fade as the gangsa rail's do
        // (`InstrumentCardView`): the content to 0.55, then the whole card by up
        // to 0.55 again, so the pair read as one design.
        return content
            .opacity(1 - 0.45 * away)
            .padding(16)
            .frame(width: Self.cardWidth, height: height, alignment: .topLeading)
            .pickerCard(selected: abs(offset) < 0.5)
            .scaleEffect(1 - (1 - sideScale) * away)
            .opacity(1 - 0.55 * away)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kotekan.name)
                .font(.serif(26))
                // Clear of the tumpal.
                .padding(.top, 6)
                .foregroundStyle(Theme.heading)
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
                        prominence: .quiet,
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
            // How long one pass lasts, then its tempo. Nothing is scored
            // without the sensor, so the record is only shown when the caller
            // has one to beat.
            Text(bestRecord.map {
                String(
                    localized: "\(kotekan.lengthLabel) · \(kotekan.bpm) BPM · best \(Theme.percentLabel($0.accuracy))"
                )
            } ?? kotekan.specLabel)
                .font(.sans(13, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.description)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

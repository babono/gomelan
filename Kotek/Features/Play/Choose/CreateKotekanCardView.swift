//
//  CreateKotekanCardView.swift
//  Kotek
//
//  The last card in the kotekan rail: the way into Create Kotek. Same size and
//  falloff as `KotekanCardView` so it moves with the rest of the rail.
//

import SwiftUI

struct CreateKotekanCardView: View {
    let offset: Double

    var body: some View {
        let nearness: CGFloat = max(0, 1 - min(abs(CGFloat(offset)), 1.6) / 1.6)

        // The plus sits beside the title rather than under the blurb: the card
        // is the same fixed height as a figure card, and at the bottom it was
        // pushed out through the border.
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel("Your own", color: Theme.terracotta)
            HStack(spacing: 12) {
                Text("Create kotek")
                    .font(.serif(26))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Image(systemName: "plus")
                    .font(.symbol(18, weight: .semibold))
                    .foregroundStyle(Theme.gold)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(Theme.gold.opacity(0.6), lineWidth: 1))
            }
            Text("Write it on a piano roll, or play it on your gangsa and record it with the sensors.")
                .font(.sans(13))
                .foregroundStyle(Theme.stone)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: KotekanCardView.cardWidth, height: KotekanCardView.cardHeight, alignment: .topLeading)
        .background(
            Theme.deep.opacity(0.35 + 0.3 * nearness),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    Theme.gold.opacity(0.25 + 0.5 * nearness),
                    style: StrokeStyle(lineWidth: 1 + nearness, dash: [6, 5])
                )
        )
        .scaleEffect(0.84 + 0.16 * nearness)
        .opacity(0.35 + 0.65 * nearness)
        .allowsHitTesting(false)
    }
}

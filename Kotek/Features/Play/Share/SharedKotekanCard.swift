//
//  SharedKotekanCard.swift
//  Kotek
//
//  The figure behind a share link, drawn as the kotekan picker draws one:
//  its name, its notes (`KotekanMiniScore`), its length and tempo. A first
//  pass gave it the description instead; a figure is told apart by its
//  shape, not a sentence about it. White on a Garis edge, as a secondary
//  control stands — the gold ring and tumpal belong to the gangsa being
//  chosen beside it.
//

import SwiftUI

struct SharedKotekanCard: View {
    /// Nil while it loads: the card keeps its place, the score left blank.
    let kotekan: Kotekan?
    /// The gangsa card's, so the two stand level either side of the arrow.
    let height: CGFloat

    static let width: CGFloat = 250

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Shared with you", systemImage: "link")
                // Sentence case: the design keeps capitals for the wordmark.
                .font(.sans(12, weight: .semibold))
                .foregroundStyle(Theme.cream)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.deep, in: Capsule())

            if let kotekan {
                Text(LocalizedStringKey(kotekan.name))
                    .font(.serif(26))
                    .foregroundStyle(Theme.heading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                KotekanMiniScore(kotekan: kotekan)
                    .frame(maxHeight: .infinity)

                Text(kotekan.specLabel)
                    .font(.sans(13, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.description)
                    .lineLimit(1)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.deep)
                    .frame(width: 150, height: 24)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.deep)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(width: Self.width, height: height, alignment: .topLeading)
        .tactile(
            RoundedRectangle(cornerRadius: 20),
            fill: Theme.surface,
            outline: Theme.hairline,
            outlineWidth: 1.5,
            base: Theme.hairline,
            depth: 5
        )
        .accessibilityElement(children: .combine)
    }
}

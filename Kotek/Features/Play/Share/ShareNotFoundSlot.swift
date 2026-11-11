//
//  ShareNotFoundSlot.swift
//  Kotek
//
//  Where the figure would be when the link leads nowhere: a dashed, empty
//  card with a broken link in it — the add screen's empty gangsa slot, for
//  the figure's side. An empty middle, which it was, read as still loading.
//

import SwiftUI

struct ShareNotFoundSlot: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "link")
                .font(.symbol(28, weight: .semibold))
                .foregroundStyle(Theme.hairline)
                // Struck through, in the misses' red: the link is broken.
                .overlay {
                    Capsule()
                        .fill(Theme.destructive)
                        .frame(width: 44, height: 3)
                        .rotationEffect(.degrees(45))
                }
            Text("This link is empty")
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(Theme.description)
        }
        .frame(width: SharedKotekanCard.width, height: 150)
        .background(Theme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
        )
        .accessibilityElement(children: .combine)
    }
}

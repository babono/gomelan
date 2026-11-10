//
//  ShareEmptyGangsaSlot.swift
//  Kotek
//
//  Where the gangsa cards go when the player has none yet: a dashed slot the
//  size of a gangsa card, with the way to add one inside it — as on Choose
//  your gangsa's empty state.
//

import SwiftUI

struct ShareEmptyGangsaSlot: View {
    let height: CGFloat
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            GangsaTable(keyCount: 10, animated: false, full: true)
                .frame(width: 130, height: GangsaTable.height(for: 130, full: true))
                .opacity(0.4)
                .accessibilityHidden(true)
            Text("No gangsa yet")
                .font(.serif(24))
                .foregroundStyle(Theme.description)
            AppButton(title: "Add a gangsa", systemImage: "plus", prominence: .primary, size: .compact, action: onAdd)
        }
        .frame(width: InstrumentCardView.width, height: height)
        .background(Theme.deep.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }
}

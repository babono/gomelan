//
//  AppChip.swift
//  Kotek
//
//  A button that is also a choice: the instrument the piano roll lays down,
//  the tool you have armed. Selected is solid gold with dark type — one colour
//  for every choice, not a stroke (how these used to say it, each with its own
//  radius and stroke opacity) and not each choice's own colour, which was far
//  too loud.
//

import SwiftUI

struct AppChip<Label: View>: View {
    var isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                // A chip never wraps: in a crowded row SwiftUI would rather
                // break "Klentong" into four lines than let the row overflow.
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .font(.sans(14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.onGlassFill : Theme.stone)
                .padding(.horizontal, 16)
                .frame(minHeight: Theme.tapTarget)
                .controlSurface(isSelected ? .selected : .standard)
                .contentShape(Capsule())
        }
        .buttonStyle(KajarButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

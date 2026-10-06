//
//  HalfSwitch.swift
//  Kotek
//
//  Change sides (Polos/Sangsih) mid-session without stopping.
//

import SwiftUI

struct HalfSwitch: View {
    let chosenHalf: KotekanHalf
    let onSelect: (KotekanHalf) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach([KotekanHalf.polos, .sangsih]) { half in
                let selected = chosenHalf == half
                Button {
                    onSelect(half)
                } label: {
                    Text(half.title)
                        .font(.sans(12, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(1.4)
                        .foregroundStyle(selected ? Theme.ink : Theme.copper)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .background(
                            selected ? Theme.copper : .clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.kajar)
                .accessibilityAddTraits(
                    selected ? [.isButton, .isSelected] : .isButton
                )
            }
        }
        .padding(2)
        .overlay(
            Capsule().strokeBorder(Theme.copper.opacity(0.45), lineWidth: 1)
        )
    }
}

//
//  HalfPicker.swift
//  Kotek
//
//  Polos / Sangsih as one joined switch — which half you play, and which the
//  piano roll writes. It was built twice, here and in Create; this is the
//  practice screen's version, the one that was right: a quiet capsule with a
//  solid gold segment on it. A pair of chips in each half's own colour was
//  tried and was far too loud.
//

import SwiftUI

struct HalfPicker: View {
    /// The half drawn as selected, or nil when neither is — the piano roll is
    /// writing a colotomic instrument instead, and remembers the half without
    /// showing it.
    var selection: KotekanHalf?
    let onSelect: (KotekanHalf) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach([KotekanHalf.polos, .sangsih]) { half in
                segment(half)
            }
        }
        .padding(4)
        .flatGlass()
    }

    private func segment(_ half: KotekanHalf) -> some View {
        let selected = selection == half
        return Button {
            onSelect(half)
        } label: {
            Text(half.title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .font(.sans(12, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(selected ? Theme.onGlassFill : Theme.cream)
                .padding(.horizontal, 16)
                // 36 inside the 4pt inset is the 44 tap target.
                .frame(minHeight: Theme.tapTarget - 8)
                .background(selected ? Theme.gold : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(KajarButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

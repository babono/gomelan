//
//  GangsaTypePicker.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// Pemade or kantilan — the same instrument an octave apart, so this only
/// names the gangsa. Asked here because it is the one other fact about the
/// instrument the camera cannot see.
struct GangsaTypePicker: View {
    @Binding var selectedType: GangsaType

    var body: some View {
        HStack(spacing: 0) {
            ForEach(GangsaType.allCases) { option in
                let selected = selectedType == option
                Button {
                    selectedType = option
                } label: {
                    Text(option.title)
                        .font(.sans(13, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(1.4)
                        .foregroundStyle(selected ? Theme.ink : Theme.charcoal)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 18)
                        .background(
                            selected ? Theme.buttonFill : .clear,
                            in: RoundedRectangle(cornerRadius: Theme.radius - 2)
                        )
                }
                .buttonStyle(.kajar)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(Theme.charcoal.opacity(0.15), lineWidth: 1)
        )
    }
}

//
//  AppIconButton.swift
//  Kotek
//
//  A round button holding one symbol: back, undo, play, trash, settings.
//

import SwiftUI

struct AppIconButton: View {
    let systemImage: String
    /// What VoiceOver hears. A bare symbol's default label never says what the
    /// button does: "Delete Pemade 1", not "trash".
    let label: String
    var prominence = AppButton.Prominence.secondary
    var size = AppButtonSize.regular
    var tint: Color?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.symbol(size.symbolPoints, weight: .semibold))
                .foregroundStyle(prominence.labelColor(tint: tint, enabled: isEnabled))
                .appControlSurface(
                    size: size,
                    shape: .circle,
                    prominence: prominence,
                    tint: prominence == .primary ? tint : nil
                )
        }
        .buttonStyle(.appPlain)
        .accessibilityLabel(label)
    }
}

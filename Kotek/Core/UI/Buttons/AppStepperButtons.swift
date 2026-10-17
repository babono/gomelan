//
//  AppStepperButtons.swift
//  Kotek
//
//  The − | + pair beside a number. One surface behind two plain buttons, with
//  a divider so they read as a pair; holding either repeats.
//

import SwiftUI

struct AppStepperButtons: View {
    var canDecrement: Bool
    var canIncrement: Bool
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", label: "Decrease", enabled: canDecrement, action: decrement)
            Rectangle().fill(Theme.cream.opacity(0.2)).frame(width: 1, height: 16)
            stepButton("plus", label: "Increase", enabled: canIncrement, action: increment)
        }
        .flatGlass()
    }

    private func stepButton(
        _ symbol: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.symbol(12, weight: .bold))
                .foregroundStyle(Theme.cream.opacity(enabled ? 1 : 0.25))
                .frame(width: Theme.tapTarget, height: Theme.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(KajarButtonStyle())
        .buttonRepeatBehavior(.enabled)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

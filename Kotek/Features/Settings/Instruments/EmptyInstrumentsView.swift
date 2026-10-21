//
//  EmptyInstrumentsView.swift
//  Kotek
//
//  Empty state view shown when no gangsa profiles have been saved yet.
//

import SwiftUI

struct EmptyInstrumentsView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tuningfork")
                .font(.symbol(32))
                .foregroundStyle(Theme.buttonFill)

            Text("No gangsa yet")
                .font(.serif(30))
                .foregroundStyle(Theme.cream)

            Text(
                "Every gamelan is tuned differently, so Kotek learns your gangsa — where the keys are and how they sound."
            )
            .font(.sans(15))
            .foregroundStyle(Theme.cream.opacity(0.62))
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .frame(maxWidth: 440)

            // Solid, not glass: an empty state is content, and glass is for
            // the controls that float above it.
            AppButton(title: "Set up · 4 steps", prominence: .primary, size: .large) {
                onAdd()
            }
            .padding(.top, 4)
        }
        .padding(24)
    }
}

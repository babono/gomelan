//
//  SearchAndCreateBar.swift
//  Kotek
//
//  The row above a picker's rail on Choose your gangsa and Choose your
//  kotekan: finding one by name, and adding a new one. Shared so the two
//  pickers stay one design — they were drawn separately and drifted.
//
//  The magnifying glass grows sideways into the field, right where it was
//  tapped, beside the create button. It used to open a bar at the bottom over
//  the keyboard, iOS-style, which put the field a screen away from the button
//  that opened it.
//

import SwiftUI

struct SearchAndCreateBar: View {
    @Binding var query: String
    let prompt: String
    let createTitle: String
    let onCreate: () -> Void

    /// The magnifying glass opened into a field.
    @State private var searching = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            if searching {
                field
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.2, anchor: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else {
                AppIconButton(systemImage: "magnifyingglass", label: prompt) {
                    setSearching(true)
                }
                .transition(.opacity)
            }
            AppButton(createTitle, systemImage: "plus", action: onCreate)
        }
        // No side padding: flush to the safe-area edge, where the top bar's
        // buttons, the footer's and the carousel's outer cards all end.
        .padding(.bottom, 4)
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.symbol(14, weight: .medium))
                .foregroundStyle(Theme.stone)
            TextField(prompt, text: $query)
                .font(.sans(15))
                .foregroundStyle(Theme.cream)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                // Focused once it exists — set in the same tick as
                // `searching`, the field wasn't there yet to take it.
                .onAppear { focused = true }
            Button { setSearching(false) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.symbol(16))
                    .foregroundStyle(Theme.stone)
                    .frame(width: Theme.tapTarget, height: Theme.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.kajar)
            .accessibilityLabel("Close search")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(width: 280, height: Theme.tapTarget)
        // The same flat wash as the buttons beside it.
        .flatGlass()
    }

    /// Closing clears the query too — a hidden filter would leave the rail
    /// mysteriously short.
    private func setSearching(_ on: Bool) {
        if !on { focused = false }
        withAnimation(.snappy(duration: 0.25)) {
            searching = on
            if !on { query = "" }
        }
    }
}

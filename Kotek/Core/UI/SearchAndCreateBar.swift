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
//  The grow is the system's glass morph: the circle and the field share one
//  `glassEffectID` inside a `GlassEffectContainer`, so the glass itself flows
//  from one shape into the other. It was a scale-and-fade the app drew,
//  which looked like two things swapping rather than one thing opening.
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
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                if searching {
                    field
                } else {
                    Button { setSearching(true) } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.symbol(17, weight: .semibold))
                            .foregroundStyle(Theme.cream)
                            .frame(width: AppButtonSize.regular.height, height: AppButtonSize.regular.height)
                            .glassEffect(.regular.tint(Theme.glassTint).interactive(), in: Circle())
                            .glassEffectID("search", in: glass)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.appPlain)
                    .accessibilityLabel(prompt)
                }
                AppButton(title: createTitle, trailingSystemImage: "plus", size: .regular, action: onCreate)
            }
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
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.appPlain)
            .accessibilityLabel("Close search")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(width: 280, height: 44)
        .glassEffect(.regular.tint(Theme.glassTint).interactive(), in: Capsule())
        .glassEffectID("search", in: glass)
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

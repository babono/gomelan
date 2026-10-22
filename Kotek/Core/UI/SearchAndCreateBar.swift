//
//  SearchAndCreateBar.swift
//  Kotek
//
//  The row under a picker's rail on Choose your gangsa and Choose your
//  kotekan: finding one by name, and adding a new one. Shared so the two
//  pickers stay one design — they were drawn separately and drifted.
//
//  The field is always open, bottom left, with + bottom right. It used to be
//  a magnifying glass up top that morphed into the field beside a labelled
//  Create button; with the cards now the way on (a tap starts, Start and Next
//  are gone) the top bar carries Duet and ⋯, and the bottom had room for a
//  field that doesn't need opening first.
//

import SwiftUI

struct SearchAndCreateBar: View {
    @Binding var query: String
    let prompt: String
    /// VoiceOver's name for the +.
    let createTitle: String
    let onCreate: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                field
                Spacer(minLength: 0)
                AppIconButton(systemImage: "plus", label: createTitle, action: onCreate)
            }
        }
        // No side padding: flush to the safe-area edge, where the top bar's
        // buttons and the rail's outer cards end.
        .padding(.bottom, Theme.footerBottom)
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
            if !query.isEmpty {
                // Clears and lets go of the keyboard: a hidden filter would
                // leave the rail mysteriously short.
                Button {
                    query = ""
                    focused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.symbol(16))
                        .foregroundStyle(Theme.stone)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.appPlain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(width: 280, height: 44)
        .glassEffect(.regular.tint(Theme.glassTint).interactive(), in: Capsule())
    }
}

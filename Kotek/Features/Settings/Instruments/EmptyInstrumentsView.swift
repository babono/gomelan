//
//  EmptyInstrumentsView.swift
//  Kotek
//
//  Empty state view shown when no gangsa profiles have been saved yet.
//
//  The November 2026 redesign: Kipli explains, and a dashed "add" card waits
//  beside him. It was a tuning-fork icon, "No gangsa yet", a paragraph on
//  why every gamelan is different and a "Set up · 4 steps" button — the
//  steps have been three since the camera fit came out of setup, and the
//  why is better said by Kipli in one line than by a paragraph.
//

import SwiftUI

struct EmptyInstrumentsView: View {
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            KipliGuide(
                message: "Let's set up your gangsa together. It only takes a minute.",
                detail: "You'll name it, let me hear each bilah once, and attach sensors if you have them.",
                style: .intro
            )
            .frame(maxWidth: 360, alignment: .leading)

            addCard
        }
        .padding(24)
    }

    /// The mockup's dashed card: a slot where the first gangsa will go.
    private var addCard: some View {
        Button(action: onAdd) {
            VStack(spacing: 16) {
                // The design system's "Add a gangsa": a quiet Krem circle,
                // as the design system draws it, rather than a red one.
                Image(systemName: "plus")
                    .font(.symbol(22, weight: .semibold))
                    .foregroundStyle(Theme.cream)
                    .frame(width: 48, height: 48)
                    .background(Theme.deep, in: Circle())
                Text("Add your first gangsa")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.cream)
            }
            .frame(width: 220, height: 200)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.appPlain)
    }
}

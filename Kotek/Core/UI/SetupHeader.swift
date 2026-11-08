//
//  SetupHeader.swift
//  Kotek
//
//  The top of each step of adding a gangsa (the November 2026 redesign):
//  a way out on the left, "STEP 2 OF 3" and its three bars in the middle, a
//  way past on the right when the step can be skipped.
//
//  Three steps, and the bar says which: tell Kipli about the gangsa
//  (`KeyCountView`), let him hear each bilah (`NoteCaptureView`), fit the
//  sensors (`ControllerSetupView`). The bars fill in Merah up to the step you
//  are on, the rest Krem — the design system's "STEP 2 OF 3". (The first
//  mockup drew the current bar orange and the others gold, which read as
//  three different states rather than progress.)
//

import SwiftUI

struct SetupHeader: View {
    /// 1-based.
    let step: Int
    var total = 3
    /// "Cancel" as a word, as on the first step; nil draws a back button.
    var leadingTitle: LocalizedStringKey?
    let onLeading: () -> Void
    var trailingTitle: LocalizedStringKey?
    var onTrailing: (() -> Void)?
    /// A "?" for the step's guide, beside the way past.
    var onInfo: (() -> Void)?
    var infoLabel: LocalizedStringKey = "How Kotek works"

    var body: some View {
        ZStack {
            HStack {
                if let leadingTitle {
                    textButton(leadingTitle, action: onLeading)
                } else {
                    AppIconButton(systemImage: "chevron.left", label: "Back", action: onLeading)
                }
                Spacer()
                if let onInfo {
                    AppIconButton(systemImage: "questionmark", label: infoLabel, action: onInfo)
                }
                if let trailingTitle, let onTrailing {
                    textButton(trailingTitle, action: onTrailing)
                }
            }

            VStack(spacing: 6) {
                Text("Step \(step) of \(total)")
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.description)
                HStack(spacing: 4) {
                    ForEach(1 ... total, id: \.self) { i in
                        Capsule()
                            .fill(i <= step ? Theme.primary : Theme.deep)
                            .frame(width: 32, height: 4)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Step \(step) of \(total)"))
        }
        .padding(.top, 14)
    }

    /// The design system's plain "Skip": words in Merah tua, not a button, so
    /// the step's one filled button is its way on.
    private func textButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.sans(17, weight: .semibold))
                .foregroundStyle(Theme.merahTua)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.appPlain)
    }
}

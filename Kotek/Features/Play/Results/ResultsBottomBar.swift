//
//  ResultsBottomBar.swift
//  Kotek
//
//  Bottom action bar offering retry or returning to kotekan selection.
//

import SwiftUI

struct ResultsBottomBar: View {
    let onChooseAnother: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Compact: the bar shares a half-width column with the feedback
            // now, and at full size "Choose another kotekan" pushed Retry off
            // the edge of the screen.
            PillButton(title: "Other kotekan", style: .outlined, tint: Theme.charcoal, compact: true) {
                onChooseAnother()
            }
            PillButton(title: "Retry", style: .filled, tint: Theme.terracotta, compact: true) {
                onRetry()
            }
            Spacer()
        }
        .padding(.top, 2)
        .padding(.bottom, 8)
    }
}

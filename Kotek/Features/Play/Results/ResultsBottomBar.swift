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
        // Full words again: the bar has the screen's width since the graph
        // column went, and "Other kotekan" / "Retry" were only ever short to fit
        // half of it.
        HStack(spacing: 14) {
            AppButton(title: "Choose another kotekan", size: .regular) {
                onChooseAnother()
            }
            AppButton(title: "Play again", systemImage: "play.fill", prominence: .primary, size: .regular) {
                onRetry()
            }
        }
        .padding(.top, 2)
        .padding(.bottom, Theme.footerBottom)
    }
}

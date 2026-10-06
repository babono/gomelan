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
            PillButton(title: "Choose another kotekan", style: .outlined, tint: Theme.charcoal) {
                onChooseAnother()
            }
            PillButton(title: "Retry", style: .filled, tint: Theme.terracotta) {
                onRetry()
            }
            Spacer()
        }
        .padding(.top, 2)
        .padding(.bottom, 8)
    }
}

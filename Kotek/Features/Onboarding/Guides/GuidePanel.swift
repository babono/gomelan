//
//  GuidePanel.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// The shell: dimmed backdrop, panel, title and dismiss on one row, two columns.
///
/// A CUSTOM overlay rather than `.sheet`. A system sheet on a landscape phone
/// arrives as a card with its own grabber, its own chrome and its own idea of
/// what a background is. This is a dimmed backdrop and a panel.
struct GuidePanel<Content: View>: View {
    let title: String
    /// An asset to draw in place of the title.
    var titleImage: String?
    var onClose: () -> Void
    /// Whether the body scrolls. True for the columns; false for anything that manages its own height.
    var scrolls: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            // Tapping outside closes.
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture {
                    Task { @concurrent in
                        await KajarTick.strike()
                    }
                    onClose()
                }

            panel
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
        }
        .transition(.opacity)
    }

    private var body_: some View {
        content
            .padding(.horizontal, 26)
            .padding(.top, 6)
            .padding(.bottom, 16)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if scrolls {
                ScrollView { body_ }
            } else {
                body_
            }
        }
        .background(Theme.deep, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Theme.cream.opacity(0.12), lineWidth: 1)
        )
        .frame(maxWidth: 900)
    }

    /// Title and dismiss on ONE row.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            if let titleImage {
                Image(titleImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 26)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                    .accessibilityLabel(title)
            } else {
                Text(title)
                    .font(.serif(24))
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 16)

            PillButton(
                title: "Got it",
                style: .filled,
                compact: true,
                action: onClose
            )
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 8 }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }
}

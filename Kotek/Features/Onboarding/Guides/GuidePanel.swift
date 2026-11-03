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
    let title: LocalizedStringKey
    /// What Kipli says under the title. With him there, the title has the
    /// top row to itself, set as written, and Got it moves down beside his
    /// bubble — the designer's "How kotekan works" layout.
    var kipli: LocalizedStringResource?
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
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Theme.cream.opacity(0.12), lineWidth: 1)
        )
        .frame(maxWidth: 900)
    }

    @ViewBuilder
    private var header: some View {
        if let kipli {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.serif(28))
                    .foregroundStyle(Theme.heading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(alignment: .center, spacing: 16) {
                    KipliGuide(message: kipli)
                        .frame(maxWidth: 460, alignment: .leading)
                    Spacer(minLength: 0)
                    gotIt(.regular)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .padding(.bottom, 6)
        } else {
            titleRow
        }
    }

    private func gotIt(_ size: AppButtonSize) -> some View {
        // Solid: it sits on the guide's own card, where glass would have
        // nothing to refract and would be glass in the content layer.
        AppButton(
            title: "Got it",
            prominence: .primary,
            size: size,
            action: onClose
        )
    }

    /// Title and dismiss on ONE row.
    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.serif(24))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Theme.heading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 16)

            gotIt(.compact)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 8 }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }
}

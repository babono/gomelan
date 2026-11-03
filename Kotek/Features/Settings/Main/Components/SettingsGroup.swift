//
//  SettingsGroup.swift
//  Kotek
//
//  The grouped rows Settings' pages are made of: a small header, then rows in
//  one rounded block with hairlines between them, a control on the right.
//

import SwiftUI

struct SettingsGroup<Content: View>: View {
    let header: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(header, color: Theme.stone)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content
            }
            .background(Theme.cream.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    private static var inset: CGFloat {
        16
    }

    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    /// A hairline above, for every row but a group's first.
    var divider = true
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.sans(15))
                    .foregroundStyle(Theme.cream)
                if let subtitle {
                    Text(subtitle)
                        .font(.sans(12))
                        .foregroundStyle(Theme.stone)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        // Room above and below as well as at the sides: with only a minimum
        // height, a row whose subtitle wraps (Damping guide) ran its text to
        // the block's edges while a one-line row floated in the middle.
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 12)
        .frame(minHeight: 56)
        .overlay(alignment: .top) {
            if divider {
                Rectangle().fill(Theme.cream.opacity(0.08)).frame(height: 1).padding(.leading, Self.inset)
            }
        }
    }
}

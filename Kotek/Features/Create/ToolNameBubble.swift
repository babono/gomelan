//
//  ToolNameBubble.swift
//  Kotek
//
//  The name of a piano-roll tool, shown beside its icon.
//

import SwiftUI

struct ToolNameBubble: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.sans(13, weight: .semibold))
            .foregroundStyle(Theme.cream)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(height: 30)
            .glassEffect(.regular.tint(Theme.glassTint), in: Capsule())
            .accessibilityHidden(true)
    }
}

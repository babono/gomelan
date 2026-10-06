//
//  GuideComponents.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// The two-column body the explainer panels use.
struct GuideColumns<Left: View, Right: View>: View {
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        HStack(alignment: .top, spacing: 30) {
            left.frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Theme.cream.opacity(0.12)).frame(width: 1)
            right.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A titled paragraph.
struct GuideBlock: View {
    let heading: String
    let text: String

    init(_ heading: String, _ text: String) {
        self.heading = heading
        self.text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(heading, color: Theme.gold)
            Text(text)
                .font(.sans(13))
                .foregroundStyle(Theme.cream.opacity(0.75))
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The prose under a column heading.
struct GuideLead: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.sans(13))
            .foregroundStyle(Theme.cream.opacity(0.75))
            .lineSpacing(1)
            .fixedSize(horizontal: false, vertical: true)
    }
}

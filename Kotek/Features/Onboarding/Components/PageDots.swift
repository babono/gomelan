//
//  PageDots.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// Shared custom page indicator dots styled to the Kotek theme.
/// Used by OnboardingView and GuideSlides.
struct PageDots: View {
    let count: Int
    @Binding var index: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0 ..< count, id: \.self) { i in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { index = i }
                } label: {
                    Circle()
                        .fill(i == index ? Theme.buttonFill : Theme.cream.opacity(0.22))
                        .frame(width: 7, height: 7)
                        // Drawn at 7pt and hit at 30. A row of seven-point
                        // targets is a row of near-misses.
                        .frame(width: 30, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.kajar)
                .accessibilityLabel("Slide \(i + 1) of \(count)")
            }
        }
        .frame(height: 26)
    }
}

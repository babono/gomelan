//
//  FramingBottomBar.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// One line caption and action button strip for framing.
struct FramingBottomBar: View {
    let cameraReady: Bool
    let onContinue: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            SectionLabel(
                "Fit every key inside the frame — fill it as much as you can",
                color: Theme.copper
            )
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Spacer(minLength: 12)

            PillButton(
                title: "Continue",
                trailingSystemImage: "arrow.right",
                style: .filled,
                tint: Theme.copper,
                compact: true,
                action: onContinue
            )
            .disabled(!cameraReady)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: [.bottom, .horizontal])
        )
    }
}

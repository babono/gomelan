//
//  OnboardingSlideLayout.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// A slide is a picture and a column of type, side by side, and which side the
/// picture takes is the only thing that varies. Held in one place so the type
/// column cannot drift between slides — it is the same title, the same lead and
/// the same button on all three.
struct OnboardingSlideLayout<Art: View, Action: View>: View {
    enum ArtSide { case leading, trailing }

    var artSide: ArtSide = .leading
    let titleTop: String
    let titleBottom: String
    let lead: LocalizedStringKey
    @ViewBuilder var art: Art
    @ViewBuilder var action: Action

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height

            HStack(spacing: 28) {
                if artSide == .leading { artColumn }
                textColumn(height: h)
                if artSide == .trailing { artColumn }
            }
            .padding(.horizontal, 44)
            .padding(.top, 36)
            .padding(.bottom, 36)
        }
    }

    private var artColumn: some View {
        Color.clear
            .overlay { art }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private func textColumn(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            let titleSize = min(52, max(30, height * 0.13))

            Group {
                Text(titleTop).foregroundStyle(Theme.cream)
                Text(titleBottom).foregroundStyle(Theme.buttonFill)
            }
            .font(.serif(titleSize))
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            Text(lead)
                .font(.sans(16))
                .foregroundStyle(Theme.cream.opacity(0.78))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            action.padding(.top, 22)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

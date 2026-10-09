//
//  SplashView.swift
//  Kotek
//
//  The launch screen: the wordmark, a loading pill, the Mekar Bhuana credit
//  underneath, and who built it along the foot.
//

import SwiftUI

struct SplashView: View {
    /// 0…1. Drives the pill.
    var progress: Double

    /// Who built it, along the foot.
    private var builtAt: some View {
        (
            HStack(spacing: 4) {
                Text("Built at  ").foregroundStyle(Theme.cream.opacity(0.5))
                Text(Image(systemName: "apple.logo")).foregroundStyle(Theme.cream.opacity(0.82))
                Text("  Apple Developer Academy Bali  ").foregroundStyle(Theme.cream.opacity(0.82))
                Text("for the gamelan community.").foregroundStyle(Theme.cream.opacity(0.5))
            }
        )
        .font(.sans(12))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityLabel("Built at Apple Developer Academy Bali, for the gamelan community")
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                Theme.ground.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer().frame(height: KotekWordmark.topInset(in: h))

                    KotekWordmark(width: KotekWordmark.width(in: w))

                    Spacer().frame(height: h * 0.06)

                    ProgressPill(progress: progress)
                        .frame(width: min(280, w * 0.32), height: min(38, h * 0.10))

                    Spacer().frame(height: h * 0.05)

                    Text("in collaboration with")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Theme.cream.opacity(0.72))

                    Spacer().frame(height: h * 0.03)

                    Image("logo-mekarbhuana")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: min(260, w * 0.29))

                    Spacer(minLength: 0)

                    builtAt

                    Spacer().frame(height: h * 0.06)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea()
    }
}

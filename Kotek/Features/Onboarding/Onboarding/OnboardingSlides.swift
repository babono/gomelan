//
//  OnboardingSlides.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import Lottie
import SwiftUI

struct WelcomeSlide: View {
    var onNext: () -> Void

    var body: some View {
        OnboardingSlideLayout(
            artSide: .leading,
            titleTop: "Welcome to",
            titleBottom: "Kotek",
            lead: "Reimagining Balinese heritage through interactive play."
        ) {
            SpinningMark()
        } action: {
            PillButton(
                title: "Next",
                trailingSystemImage: "arrow.right",
                style: .filled,
                action: onNext
            )
        }
    }
}

struct InterlockSlide: View {
    var onNext: () -> Void

    var body: some View {
        OnboardingSlideLayout(
            artSide: .leading,
            titleTop: "Master the",
            titleBottom: "Interlock",
            lead: "Learn to play the **Polos** and **Sangsih** parts that form the core of gamelan rhythm."
        ) {
            VStack(spacing: 10) {
                DotLottieArt(name: "polos")
                DotLottieArt(name: "sangsih")
            }
        } action: {
            PillButton(
                title: "Next",
                trailingSystemImage: "arrow.right",
                style: .filled,
                action: onNext
            )
        }
    }
}

struct TrackingSlide: View {
    var onFinish: () -> Void

    var body: some View {
        OnboardingSlideLayout(
            artSide: .trailing,
            titleTop: "Precision",
            titleBottom: "Tracking",
            lead: "Use your **camera** to get real-time feedback on your technique and timing."
        ) {
            Image("precision-tracking")
                .resizable()
                .aspectRatio(contentMode: .fit)
        } action: {
            PillButton(title: "Finish", style: .filled, action: onFinish)
        }
    }
}

// MARK: - Artwork Components

/// The mallet pinwheel, turning.
struct SpinningMark: View {
    @State private var turning = false
    private static let period: Double = 24

    var body: some View {
        Image("icon-kotek")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(
                .linear(duration: Self.period).repeatForever(autoreverses: false),
                value: turning
            )
            .onAppear { turning = true }
            .padding(12)
    }
}

/// One dotLottie file, looping.
struct DotLottieArt: View {
    let name: String

    var body: some View {
        LottieView { try await DotLottieFile.named(name) }
            .resizable()
            .looping()
            .backgroundBehavior(.pauseAndRestore)
    }
}

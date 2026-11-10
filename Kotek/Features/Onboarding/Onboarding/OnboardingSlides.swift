//
//  OnboardingSlides.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

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
            NawaSangaMark()
        } action: {
            AppButton(
                title: "Next",
                prominence: .primary,
                size: .large,
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
            InterlockArt()
        } action: {
            AppButton(
                title: "Next",
                prominence: .primary,
                size: .large,
                action: onNext
            )
        }
    }
}

struct TrackingSlide: View {
    var onSensors: () -> Void
    var onFinish: () -> Void

    var body: some View {
        OnboardingSlideLayout(
            artSide: .leading,
            titleTop: "Precision",
            titleBottom: "Tracking",
            lead: "Fit **sensors** under your bilah to get real-time feedback on your timing."
        ) {
            TrackingArt()
        } action: {
            HStack(spacing: 12) {
                AppButton(title: "Finish", prominence: .primary, size: .large, action: onFinish)
                AppButton(title: "How the sensors work", prominence: .secondary, size: .large, action: onSensors)
            }
        }
    }
}

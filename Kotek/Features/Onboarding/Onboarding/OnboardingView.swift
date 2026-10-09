//
//  OnboardingView.swift
//  Kotek
//
//  The introduction: three full-screen slides, shown unasked exactly once on a
//  first run and after that only when somebody asks for it again from the help
//  button on the instrument picker.
//

import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    #if DEBUG
        // `-onboardingPage N` opens on a later slide, for App Store screenshots —
        // see `ScreenshotScenes.swift`.
        @State private var index = UserDefaults.standard.integer(
            forKey: "onboardingPage"
        )
    #else
        @State private var index = 0
    #endif
    private static let slideCount = 3

    var body: some View {
        ZStack {
            PatternBackground()

            TabView(selection: $index) {
                WelcomeSlide(onNext: next).tag(0)
                InterlockSlide(onNext: next).tag(1)
                TrackingSlide(onFinish: finish).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                Spacer()
                PageDots(count: Self.slideCount, index: $index)
                    .padding(.bottom, 10)
            }
        }
        .transition(.opacity)
    }

    private func next() {
        withAnimation(.snappy(duration: 0.3)) {
            index = min(index + 1, Self.slideCount - 1)
        }
    }

    private func finish() {
        withAnimation(.easeInOut(duration: 0.3)) {
            onFinish()
        }
    }
}

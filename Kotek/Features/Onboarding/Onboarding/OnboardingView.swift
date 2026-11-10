//
//  OnboardingView.swift
//  Kotek
//
//  The introduction: three full-screen slides, shown unasked exactly once on a
//  first run and after that only when somebody asks for it again from the help
//  button on the instrument picker.
//
//  Skip, top right, on the first two (the designer's 02c Onboarding); the last
//  has Finish, and "How the sensors work", which opens the website's sensor
//  explainer over it.
//

import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    #if DEBUG
        /// `-onboardingPage N` opens on a later slide, for App Store screenshots —
        /// see `ScreenshotScenes.swift`.
        @State private var index = UserDefaults.standard.integer(
            forKey: "onboardingPage"
        )
    #else
        @State private var index = 0
    #endif
    private static let slideCount = 3
    #if DEBUG
        /// `-onboardingSensors YES` opens over the last slide with "How the
        /// sensors work" up.
        @State private var showingSensors = UserDefaults.standard.bool(forKey: "onboardingSensors")
    #else
        @State private var showingSensors = false
    #endif

    var body: some View {
        ZStack {
            PatternBackground()

            TabView(selection: $index) {
                WelcomeSlide(onNext: next).tag(0)
                InterlockSlide(onNext: next).tag(1)
                TrackingSlide(onSensors: openSensors, onFinish: finish).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                Spacer()
                AppPageDots(count: Self.slideCount, index: $index)
                    .padding(.bottom, 10)
            }

            if index < Self.slideCount - 1 {
                Button("Skip", action: finish)
                    .font(.sans(17, weight: .semibold))
                    .foregroundStyle(Theme.merahTua)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(.appPlain)
                    .padding(.top, 14)
                    .padding(.trailing, 28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            if showingSensors {
                GuidePanel(
                    title: "How the sensors work",
                    kipli: "Every strike makes the bilah vibrate. That vibration is what Kotek reads.",
                    onClose: closeSensors,
                    scrolls: false
                ) {
                    SensorHowView()
                }
            }
        }
        .transition(.opacity)
    }

    private func next() {
        withAnimation(.snappy(duration: 0.3)) {
            index = min(index + 1, Self.slideCount - 1)
        }
    }

    private func openSensors() {
        withAnimation(.easeOut(duration: 0.2)) { showingSensors = true }
    }

    private func closeSensors() {
        withAnimation(.easeOut(duration: 0.2)) { showingSensors = false }
    }

    private func finish() {
        withAnimation(.easeInOut(duration: 0.3)) {
            onFinish()
        }
    }
}

//
//  SplashView.swift
//  Kotek
//
//  The launch screen: the wordmark, a loading pill, and the Mekar Bhuana credit
//  underneath.
//
//  It is a progress screen, not a delay. Everything it waits on is real work
//  the app used to do later and more visibly — see `Preloader` — so the time
//  spent here is time the framing screen and the first session no longer spend
//  frozen. It does have a floor, but that floor is set by the credit: a
//  collaborator's name nobody has time to read is not a credit.
//
//  Nothing on it animates in. The wordmark is simply drawn, at exactly the size
//  and place the landing screen draws it, and the pill is the only thing that
//  moves. That is what makes the hand-over work: the landing screen fades up
//  around a mark that never moved and never changed.
//

import SwiftUI

struct SplashView: View {
    /// 0…1. Drives the pill.
    var progress: Double

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                Theme.ground.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer().frame(height: KotekWordmark.topInset(in: h))

                    KotekWordmark()
                        .frame(width: KotekWordmark.width(in: w))

                    Spacer().frame(height: h * 0.10)

                    ProgressPill(progress: progress)
                        .frame(width: min(280, w * 0.32), height: min(38, h * 0.10))

                    Spacer().frame(height: h * 0.09)

                    Text("in collaboration with")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Theme.cream.opacity(0.72))

                    Spacer().frame(height: h * 0.035)

                    Image("logo-mekarbhuana")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: min(320, w * 0.36))

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Progress pill

/// The loading bar from the design: a tan track that a dark fill sweeps across.
///
/// The inversion is intentional and worth not "fixing" — the filled part is the
/// DARK one, so the bar empties of tan rather than filling with it. That is
/// what the design shows, and it is also the quieter of the two: a bright bar
/// growing across a dark screen would pull the eye off the wordmark and the
/// credit, which are the only things on this screen worth looking at.
private struct ProgressPill: View {
    var progress: Double

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(1, max(0, progress))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.bronze)
                Capsule()
                    .fill(Theme.deep)
                    // Never narrower than its own corner radius: below that a
                    // capsule collapses into a lens shape and the bar looks
                    // broken at rest rather than empty.
                    .frame(width: max(proxy.size.height, proxy.size.width * clamped))
                    .padding(3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}

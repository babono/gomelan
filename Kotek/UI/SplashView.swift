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

/// The loading bar from the design: a tan track that a dark fill sweeps across,
/// with the percentage read out in the middle of it.
///
/// The inversion is intentional and worth not "fixing" — the filled part is the
/// DARK one, so the bar empties of tan rather than filling with it. That is
/// what the design shows, and it is also the quieter of the two: a bright bar
/// growing across a dark screen would pull the eye off the wordmark and the
/// credit, which are the only things on this screen worth looking at.
///
/// The number sits still in the centre while the fill passes underneath it, so
/// no single colour can stay legible: dark type vanishes into the fill, light
/// type vanishes into the track. It is therefore drawn TWICE — once dark for
/// the tan track, then again in tan and clipped to the fill — so each digit
/// inverts exactly as the boundary crosses it, and a digit that is half-crossed
/// is half of each. One shape definition feeds both the fill and that clip, so
/// they cannot drift apart.
private struct ProgressPill: View {
    var progress: Double

    /// The gutter between the fill and the track around it.
    private let inset: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let clamped = min(1, max(0, progress))
            // Never narrower than its own height: below that a capsule collapses
            // into a lens shape and the bar looks broken at rest rather empty.
            let fillWidth = max(size.height - inset * 2,
                                (size.width - inset * 2) * clamped)

            ZStack(alignment: .leading) {
                Capsule().fill(Theme.bronze)

                fill(width: fillWidth, in: size)
                    .foregroundStyle(Theme.deep)

                readout
                    .foregroundStyle(Theme.deep)
                    .overlay {
                        readout
                            .foregroundStyle(Theme.bronze)
                            .mask(alignment: .leading) {
                                fill(width: fillWidth, in: size)
                            }
                    }
                    .frame(width: size.width, height: size.height)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }

    /// The swept portion — the fill itself, and the clip that inverts the type.
    private func fill(width: CGFloat, in size: CGSize) -> some View {
        Capsule()
            .frame(width: width, height: size.height - inset * 2)
            .offset(x: inset)
    }

    private var readout: some View { Readout(value: progress) }
}

/// The percentage itself, counting rather than jumping.
///
/// `Animatable` is the whole point of this being its own type. Progress lands in
/// three steps as each preload task finishes, and the bar glides between them
/// because `withAnimation` interpolates its width — but a plain `Text` would
/// re-render only at the steps, so the number would snap 0, 35, 70, 100 while
/// the bar slid smoothly underneath it. Two things reporting one value, visibly
/// disagreeing. Exposing the value as `animatableData` makes SwiftUI re-evaluate
/// this body at every frame of the same animation, so the digits count up with
/// the fill they sit on.
private struct Readout: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        // Monospaced digits so the number does not jitter as it counts: with
        // proportional figures the text shuffles sideways on nearly every
        // change, which is very visible on something otherwise this still.
        // Clamped here rather than by the caller: `animatableData` is fed
        // interpolated values, and an animation curve that overshoots would
        // otherwise briefly read 101%.
        Text(min(1, max(0, value)), format: .percent.precision(.fractionLength(0)))
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .tracking(0.5)
            // Decoration over the bar it duplicates; the pill already carries
            // the accessibility value, and two readings of one number is noise.
            .accessibilityHidden(true)
    }
}

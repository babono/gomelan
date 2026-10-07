//
//  ProgressPill.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// The loading bar from the design: a cream track that a deeper gold fills
/// across, with the percentage read out in the middle of it.
struct ProgressPill: View {
    var progress: Double

    /// The gutter between the fill and the track around it.
    private let inset: CGFloat = 3

    /// The swept portion. Gold deep enough to read against #FDDC8A without becoming a second accent.
    private let sweep = Color(hex: 0xBF9145)

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let clamped = min(1, max(0, progress))
            // Never narrower than its own height: below that a capsule collapses
            // into a lens shape and the bar looks broken at rest rather empty.
            let fillWidth = max(
                size.height - inset * 2,
                (size.width - inset * 2) * clamped
            )

            ZStack(alignment: .leading) {
                Capsule().fill(Theme.buttonFill)

                fill(width: fillWidth, in: size)
                    .foregroundStyle(sweep)

                readout
                    .foregroundStyle(Theme.onButtonFill)
                    .frame(width: size.width, height: size.height)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }

    /// The swept portion.
    private func fill(width: CGFloat, in size: CGSize) -> some View {
        Capsule()
            .frame(width: width, height: size.height - inset * 2)
            .offset(x: inset)
    }

    private var readout: some View {
        Readout(value: progress)
    }
}

/// The percentage itself, counting rather than jumping.
///
/// Exposing the value as `animatableData` makes SwiftUI re-evaluate
/// this body at every frame of the animation, so the digits count up with
/// the fill they sit on.
struct Readout: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        // Monospaced digits so the number does not jitter as it counts.
        Text(min(1, max(0, value)), format: .percent.precision(.fractionLength(0)))
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .tracking(0.5)
            .accessibilityHidden(true)
    }
}

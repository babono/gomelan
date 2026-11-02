//
//  PatternBackground.swift
//  Kotek
//
//  The ground every screen sits on (the November 2026 redesign): paper, and at
//  each side the silhouette of the split gate the launch screen walks through
//  — the same `pura-gate` artwork, flat in the pattern beige, its stepped
//  flank reaching in from the edge. Every screen after launch is, in the
//  story, inside the gate.
//
//  It replaced two rows of carved leaves running right forever (`bg-motif`
//  in a Core Animation `Marquee`). The redesign's mockups have no ambient
//  motion, which also retires the reason the marquee existed: a background
//  that moved needed the render server, or it stuttered whenever the main
//  thread was busy. A still one is two images.
//
//  The geometry is read off the mockups (874 x 402, 1x) and scaled by
//  `LaunchLayout.unit`: the art at 1x, its post 88pt off the screen's edge and
//  4pt above the top, so about 120pt of flank shows.
//

import SwiftUI

struct PatternBackground: View {
    /// False keeps the silhouettes off screen; turned true, they slide in from
    /// the sides. Launch holds them back until the splash has gone, so the
    /// landing screen's gate seems to become them.
    private let shown: Bool
    @State private var entered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(shown: Bool = true) {
        self.shown = shown
        _entered = State(initialValue: shown)
    }

    /// `pura-gate`'s size, and where each flank sits, in the mockups' units.
    private static let art = CGSize(width: 208, height: 434)
    private static let postOffscreen: CGFloat = 88
    private static let top: CGFloat = -4
    /// How long the flanks take to come in from the edges.
    private static let entrance = 0.9

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let u = LaunchLayout.unit(in: size)
            let art = CGSize(width: Self.art.width * u, height: Self.art.height * u)
            // Out of sight: past the edge by the width that shows.
            let away = entered ? 0 : art.width - Self.postOffscreen * u

            ZStack(alignment: .topLeading) {
                Theme.ground
                // Left: the artwork as drawn, its flank stepping down to the
                // right. Right: mirrored.
                flank
                    .frame(width: art.width, height: art.height)
                    .offset(x: -Self.postOffscreen * u - away, y: Self.top * u)
                flank
                    .scaleEffect(x: -1, y: 1)
                    .frame(width: art.width, height: art.height)
                    .offset(x: size.width - art.width + Self.postOffscreen * u + away, y: Self.top * u)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
        .onChange(of: shown) { _, now in
            guard now, !entered else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: Self.entrance)) { entered = true }
        }
    }

    private var flank: some View {
        Image("pura-gate")
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(Theme.pattern)
    }
}

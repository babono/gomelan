//
//  PelawahView.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// The carved teak frame with its row of bronze bilah — the app's own
/// instrument, drawn rather than photographed so it takes the palette.
struct Pelawah: View {
    var barCount = 10
    /// Whether the bilah play themselves.
    var animated = true

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack(alignment: .topLeading) {
                // Body: a shallow trapezium, wider at the top, like a real
                // pelawah seen slightly from above.
                Trapezium(inset: 0.045)
                    .fill(Theme.wood)
                    .frame(height: h * 0.46)
                    .offset(y: h * 0.54)

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: 0x6E4526))
                    .frame(height: h * 0.05)
                    .offset(y: h * 0.53)

                // Legs.
                ForEach([0.04, 0.905], id: \.self) { x in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(hex: 0x7A4A28))
                        .frame(width: w * 0.055, height: h * 0.6)
                        .offset(x: w * x, y: h * 0.4)
                }

                BilahRow(count: barCount, animated: animated)
                    .frame(width: w * 0.78, height: h * 0.52)
                    .offset(x: w * 0.11)
            }
        }
    }
}

/// The bilah, playing themselves.
///
/// Deliberately not random. Random strikes across ten bars look like a fault;
/// what a gangsa actually does is kotekan — two hands alternating strokes
/// within a narrow window of adjacent keys, which is the interlock the whole
/// app is about. So the home screen quietly plays one: even strokes belong to
/// one voice and odd strokes to the other, both drawn from a four-bar window
/// that moves every few seconds.
///
/// The whole thing is a pure function of the clock. Which bar is struck on
/// stroke N comes from hashing N, so nothing is stored, nothing drifts out of
/// sync, and the row can be drawn in one Canvas pass with no per-bar views to
/// diff. Bronze rings for about a second after it is hit, so the glow decays
/// rather than switching.
private struct BilahRow: View {
    let count: Int
    let animated: Bool

    /// Seconds per stroke — roughly a brisk kotekan.
    private let stroke = 0.26
    /// How long a struck bar takes to fade back to bronze.
    private let decay = 0.85
    /// How many strokes back to look for the last time a bar was hit.
    private let lookback = 5
    /// How far a struck bar is pushed down, in points.
    private let maxDip: CGFloat = 2
    /// How quickly it springs back. Much shorter than `decay` on purpose: a
    /// mallet deflects the bar for an instant and it recovers, but the tone
    /// rings on for a second afterwards.
    private let dipDecay = 0.09

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let gap = size.width * 0.015
                let barWidth =
                    (size.width - gap * CGFloat(count - 1)) / CGFloat(count)

                for i in 0 ..< count {
                    let state =
                        animated
                            ? state(bar: i, at: t)
                            : BarState(glow: i == 3 ? 1 : 0, dip: 0)
                    let lit = state.glow
                    let rect = CGRect(
                        x: (barWidth + gap) * CGFloat(i),
                        y: state.dip,
                        width: barWidth,
                        height: size.height
                    )
                    let shape = Path(roundedRect: rect, cornerRadius: 5)

                    // Bronze at rest, cream when struck.
                    let face = blend(Theme.bronze, Theme.cream, lit)
                    context.fill(shape, with: .color(face))

                    // The shaded foot of the bar.
                    let footRect = CGRect(
                        x: rect.minX,
                        y: rect.maxY - rect.height * 0.26,
                        width: rect.width,
                        height: rect.height * 0.26
                    )
                    context.fill(
                        Path(footRect),
                        with: .color(
                            blend(
                                Color(hex: 0xA98A58),
                                Color(hex: 0xD6BC85),
                                lit
                            )
                        )
                    )

                    // A struck bar lifts very slightly out of the frame.
                    if lit > 0.01 {
                        context.stroke(
                            shape,
                            with: .color(Theme.cream.opacity(lit * 0.5)),
                            lineWidth: 1.5
                        )
                    }
                }
            }
        }
    }

    /// How lit a bar is, and how far it has been pushed down.
    private struct BarState {
        var glow: Double
        var dip: CGFloat
    }

    /// Both derived from the age of the most recent strike on this bar.
    private func state(bar: Int, at t: Double) -> BarState {
        let currentStroke = Int(floor(t / stroke))
        for back in 0 ... lookback {
            let n = currentStroke - back
            guard n >= 0, struckBar(stroke: n) == bar else { continue }
            let age = t - Double(n) * stroke // most recent hit wins
            return BarState(
                glow: max(0, 1 - age / decay),
                dip: maxDip * CGFloat(exp(-age / dipDecay))
            )
        }
        return BarState(glow: 0, dip: 0)
    }

    /// Which bar the Nth stroke lands on.
    private func struckBar(stroke n: Int) -> Int {
        guard count > 4 else { return n % max(count, 1) }
        // The window wanders every 16 strokes, so the figure moves up and down
        // the instrument instead of sitting in one place.
        let span = count - 3
        let window = Int(Self.hash(n / 16) % UInt64(span))
        // Even strokes to one voice, odd to the other — offset so the two
        // interleave rather than doubling each other.
        let offsets = n.isMultiple(of: 2) ? [0, 2] : [1, 3]
        let pick = offsets[Int(Self.hash(n &+ 977) % 2)]
        return min(count - 1, window + pick)
    }

    /// splitmix64 — a cheap, well-mixed integer hash. Deterministic, so the
    /// same stroke always lands on the same bar however often it is redrawn.
    private static func hash(_ x: Int) -> UInt64 {
        var h = UInt64(bitPattern: Int64(x)) &+ 0x9E37_79B9_7F4A_7C15
        h = (h ^ (h >> 30)) &* 0xBF58_476D_1CE4_E5B9
        h = (h ^ (h >> 27)) &* 0x94D0_49BB_1331_11EB
        return h ^ (h >> 31)
    }

    private func blend(_ a: Color, _ b: Color, _ amount: Double) -> Color {
        amount <= 0 ? a : (amount >= 1 ? b : a.mix(with: b, by: amount))
    }
}

/// A rectangle whose bottom edge is narrower than its top.
private struct Trapezium: Shape {
    /// How far each bottom corner is drawn in, as a fraction of the width.
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = rect.width * inset
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - dx, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + dx, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

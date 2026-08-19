//
//  WelcomeView.swift
//  Kotek
//
//  Entry screen (PRD §8), built to the Kotek design: the name in Dream
//  Orphans over the drifting pattern, one cream key to press, and a pelawah
//  rising from the bottom edge.
//
//  Framing stays honest: this helps you take a first step, before a teacher —
//  never instead of one (§1).
//

import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var app
    @State private var music = TitleMusic()

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height

            ZStack {
                Ornaments()

                VStack(spacing: 0) {
                    Spacer().frame(height: h * 0.08)

                    Text("Kotek")
                        .font(.serif(min(76, h * 0.19)))
                        .foregroundStyle(Theme.cream)
                        .tracking(-0.5)

                    Spacer().frame(height: h * 0.09)

                    PillButton(title: "Enter", style: .filled, uppercase: false) {
                        music.stop()
                        app.begin()
                    }
                    .frame(width: 146)

                    Spacer()
                }

                // Anchored to the bottom edge and allowed to run off it, so the
                // instrument reads as continuing past the screen rather than
                // sitting on a shelf.
                VStack {
                    Spacer()
                    Pelawah()
                        .frame(width: min(470, proxy.size.width * 0.54), height: 142)
                        .offset(y: 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .onAppear { music.start() }
        // Also on the way out by any other route — a back navigation, or the
        // app being torn down — so the bed can never outlive the screen.
        .onDisappear { music.stop() }
    }
}

// MARK: - Ornaments

/// The spoked gold rosettes, drifting and breathing behind the title.
///
/// Positions are fractions of the screen rather than the design's fixed pixels,
/// so the arrangement survives a different aspect ratio instead of collecting in
/// one corner.
///
/// Motion is derived from the clock, not stored: every rosette's drift, scale
/// and rotation is a function of `t` and its own index, so there is no state to
/// update, nothing to keep in sync, and the whole field is one Canvas draw. The
/// periods are deliberately incommensurate — 0.11, 0.083, 0.23 — so the six
/// never fall into step with each other, which is what makes it read as drifting
/// rather than pulsing.
private struct Ornaments: View {
    /// x, y (fractions of the frame) and diameter in points.
    private let marks: [(x: Double, y: Double, d: Double)] = [
        (0.07, 0.10, 68), (0.86, 0.07, 74), (0.19, 0.38, 58),
        (0.76, 0.39, 62), (0.03, 0.72, 64), (0.92, 0.71, 70),
    ]
    private let spokes = 21

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                for (i, mark) in marks.enumerated() {
                    let phase = Double(i) * 1.7
                    let drift = CGPoint(x: sin(t * 0.11 + phase) * 14,
                                        y: cos(t * 0.083 + phase * 1.3) * 10)
                    let breathe = 1 + 0.09 * sin(t * 0.23 + phase * 0.7)
                    // Alternating direction so neighbours never turn together.
                    let spin = t * 0.05 * (i.isMultiple(of: 2) ? 1 : -1) + phase

                    let d = mark.d * breathe
                    let centre = CGPoint(x: mark.x * size.width + d / 2 + drift.x,
                                         y: mark.y * size.height + d / 2 + drift.y)

                    // All spokes in ONE path, so each rosette costs a single
                    // stroke rather than twenty-one.
                    var path = Path()
                    for s in 0..<spokes {
                        let angle = Double(s) / Double(spokes) * 2 * .pi + spin
                        path.move(to: CGPoint(x: centre.x + cos(angle) * d * 0.16,
                                              y: centre.y + sin(angle) * d * 0.16))
                        path.addLine(to: CGPoint(x: centre.x + cos(angle) * d * 0.5,
                                                 y: centre.y + sin(angle) * d * 0.5))
                    }
                    let fade = 0.42 + 0.16 * sin(t * 0.19 + phase)
                    context.stroke(path, with: .color(Theme.gold.opacity(fade)), lineWidth: 1.2)

                    context.fill(
                        Path(ellipseIn: CGRect(x: centre.x - 6, y: centre.y - 6,
                                               width: 12, height: 12)),
                        with: .color(Theme.gold.opacity(0.85)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Pelawah

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
    /// rings on for a second afterwards. Tying the two together would have the
    /// bar sitting depressed for as long as it glows, which reads as broken
    /// rather than struck.
    private let dipDecay = 0.09

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let gap = size.width * 0.015
                let barWidth = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)

                for i in 0..<count {
                    let state = animated ? state(bar: i, at: t)
                                         : BarState(glow: i == 3 ? 1 : 0, dip: 0)
                    let lit = state.glow
                    let rect = CGRect(x: (barWidth + gap) * CGFloat(i), y: state.dip,
                                      width: barWidth, height: size.height)
                    let shape = Path(roundedRect: rect, cornerRadius: 5)

                    // Bronze at rest, cream when struck.
                    let face = blend(Theme.bronze, Theme.cream, lit)
                    context.fill(shape, with: .color(face))

                    // The shaded foot of the bar.
                    let footRect = CGRect(x: rect.minX, y: rect.maxY - rect.height * 0.26,
                                          width: rect.width, height: rect.height * 0.26)
                    context.fill(
                        Path(footRect),
                        with: .color(blend(Color(hex: 0xA98A58), Color(hex: 0xD6BC85), lit)))

                    // A struck bar lifts very slightly out of the frame.
                    if lit > 0.01 {
                        context.stroke(shape,
                                       with: .color(Theme.cream.opacity(lit * 0.5)),
                                       lineWidth: 1.5)
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
        for back in 0...lookback {
            let n = currentStroke - back
            guard n >= 0, struckBar(stroke: n) == bar else { continue }
            let age = t - Double(n) * stroke    // most recent hit wins
            return BarState(glow: max(0, 1 - age / decay),
                            dip: maxDip * CGFloat(exp(-age / dipDecay)))
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
        var h = UInt64(bitPattern: Int64(x)) &+ 0x9E3779B97F4A7C15
        h = (h ^ (h >> 30)) &* 0xBF58476D1CE4E5B9
        h = (h ^ (h >> 27)) &* 0x94D049BB133111EB
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

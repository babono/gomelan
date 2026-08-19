//
//  WelcomeView.swift
//  Kotek
//
//  Entry screen (PRD §8), built to the Kotek design: the wordmark over the
//  drifting pattern, ornaments flying behind it, one cream key to press, and a
//  pelawah rising from the bottom edge.
//
//  The wordmark is drawn at the geometry the splash screen uses, from the same
//  shared numbers, because this screen is revealed underneath the splash rather
//  than pushed on after it — see `RootView`.
//
//  Framing stays honest: this helps you take a first step, before a teacher —
//  never instead of one (§1).
//

import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var app
    @State private var music = TitleMusic()
    /// Lives here rather than with the splash screen it belongs to, because
    /// this is the one place in launch where starting a sound is known to
    /// work — the music bed has always been audible from here. See SplashChime.
    @State private var chime = SplashChime()

    /// Where the gamelan bed sits while the opening kempur is ringing.
    ///
    /// Low enough that the gong is unmistakably the thing you hear. A kempur is
    /// nearly all low frequency, which is the part a phone speaker reproduces
    /// worst, so it needs more room than the numbers suggest — the bed being
    /// broadband means it masks the gong far more than an equal level implies.
    private static let duckedMusicLevel: Float = 0.4

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height

            ZStack {
                Ornaments()

                VStack(spacing: 0) {
                    // Geometry shared with the splash screen, not restated —
                    // the hand-over is a cross-fade around a wordmark that does
                    // not move, which only holds if both screens draw it from
                    // the same numbers. See `KotekWordmark`.
                    Spacer().frame(height: KotekWordmark.topInset(in: h))

                    KotekWordmark()
                        .frame(width: KotekWordmark.width(in: proxy.size.width))

                    Spacer().frame(height: h * 0.07)

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
        // Both start here, at launch and underneath the splash. The gong first:
        // its attack is immediate, while the bed comes up from silence.
        //
        // The bed enters DUCKED and swells afterwards, which is the only way to
        // give the kempur the room it needs. Both are already at full scale —
        // the gong cannot be turned up, and the sample deliberately is not
        // renormalised because `CuePlayer` uses it in the colotomic layer during
        // play, where its level is balanced against a limiter. So the space is
        // made by lowering everything else instead, the way it would be on a
        // desk.
        .onAppear {
            chime.strike()
            music.start(volume: Self.duckedMusicLevel)
        }
        // The swell, once the gong has fallen. Cancelled automatically if the
        // player presses Enter first, which is exactly right: the music is on
        // its way out at that point and must not be pulled back up.
        .task {
            try? await Task.sleep(for: .seconds(SplashChime.totalDuration))
            music.setLevel(1.0, fadeDuration: 1.8)
        }
        // Also on the way out by any other route — a back navigation, or the
        // app being torn down — so the bed can never outlive the screen.
        //
        // Leaving this screen is also where the capture audio configuration
        // goes back on. The app launches on `.playback` so the splash can be
        // heard; everything past here leads towards a camera and a microphone,
        // and detection needs `.measurement` in force before it gets there.
        .onDisappear {
            music.stop()
            AudioSessionManager.configure()
        }
    }
}

// MARK: - Ornaments

/// The carved ornaments drifting behind the title, forever.
///
/// Two motifs from the design (`ornament-1`, `ornament-2`) rather than a drawn
/// rosette, each one flying slowly across the screen and wrapping round to come
/// back on the other side. The wrap is what makes it a loop with no seam: the
/// travel is taken modulo the screen width plus the ornament's own size, so a
/// mark leaves one edge completely before it re-enters at the other, and the
/// arithmetic never grows however long the app is left sitting here.
///
/// Motion is derived from the clock, not stored: every ornament's position,
/// bob and rotation is a function of `t` and its own row in the table below.
/// There is no state to update, nothing to keep in sync, and the whole field is
/// one `Canvas` draw rather than a dozen views to diff every frame.
///
/// The periods are deliberately incommensurate — the drift, the bob and the
/// spin all run at unrelated rates — so the field never falls into step with
/// itself, which is what makes it read as drifting rather than marching.
private struct Ornaments: View {
    /// One flying ornament.
    ///
    /// `y` is a fraction of the height so the arrangement survives a different
    /// aspect ratio; `size` and `speed` are in points, since those should look
    /// the same on every screen. A negative `speed` flies right-to-left.
    private struct Mark {
        let art: Int
        let y: Double
        let size: Double
        let speed: Double
        /// Where in its own crossing this mark starts, 0…1, so they do not all
        /// enter together.
        let phase: Double
        let opacity: Double
        /// Turns per second. Small — these are drifting, not tumbling.
        let spin: Double
    }

    private let marks: [Mark] = [
        Mark(art: 0, y: 0.10, size: 62, speed:  11, phase: 0.05, opacity: 0.55, spin:  0.010),
        Mark(art: 1, y: 0.26, size: 44, speed: -8,  phase: 0.62, opacity: 0.42, spin: -0.014),
        Mark(art: 0, y: 0.44, size: 78, speed:  6,  phase: 0.35, opacity: 0.50, spin:  0.007),
        Mark(art: 1, y: 0.58, size: 52, speed: -13, phase: 0.88, opacity: 0.38, spin:  0.012),
        Mark(art: 0, y: 0.72, size: 48, speed:  14, phase: 0.20, opacity: 0.45, spin: -0.009),
        Mark(art: 1, y: 0.86, size: 66, speed: -9,  phase: 0.50, opacity: 0.40, spin:  0.011),
        Mark(art: 1, y: 0.18, size: 56, speed:  8,  phase: 0.74, opacity: 0.35, spin: -0.006),
        Mark(art: 0, y: 0.66, size: 40, speed: -7,  phase: 0.12, opacity: 0.44, spin:  0.015),
    ]

    /// The size the artwork is rasterised at. Every mark is drawn at this size
    /// or smaller, so the scale is always downwards — resolving a symbol at its
    /// natural 64pt and blowing it up to 78 would soften the largest ones.
    private static let symbolSize: CGFloat = 96

    var body: some View {
        // 30fps, like the pattern behind it. The fastest mark covers less than
        // half a point between frames at 120Hz, so the extra ninety redraws a
        // second would buy nothing visible — and this is ambient decoration that
        // must never compete with anything else the app is doing.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                for mark in marks {
                    guard let symbol = context.resolveSymbol(id: mark.art) else { continue }

                    // The full crossing: off one edge, across, and off the
                    // other. Taking the travel modulo this is what closes the
                    // loop seamlessly.
                    let span = size.width + mark.size
                    let travel = t * mark.speed + mark.phase * span
                    var x = travel.truncatingRemainder(dividingBy: span)
                    // Swift's remainder keeps the sign of the dividend, so a
                    // right-to-left mark would sit off-screen forever without
                    // this.
                    if x < 0 { x += span }
                    x -= mark.size

                    let bob = sin(t * 0.21 + mark.phase * 6.3) * 12
                    let centre = CGPoint(x: x + mark.size / 2,
                                         y: mark.y * size.height + bob)

                    var layer = context
                    layer.opacity = mark.opacity
                    layer.translateBy(x: centre.x, y: centre.y)
                    layer.rotate(by: .radians(t * mark.spin * 2 * .pi))
                    layer.draw(symbol,
                               in: CGRect(x: -mark.size / 2, y: -mark.size / 2,
                                          width: mark.size, height: mark.size))
                }
            } symbols: {
                // Framed rather than left at their natural size so the vector
                // artwork is rasterised big enough for the largest mark above.
                Image("ornament-1")
                    .resizable()
                    .frame(width: Self.symbolSize, height: Self.symbolSize)
                    .tag(0)
                Image("ornament-2")
                    .resizable()
                    .frame(width: Self.symbolSize, height: Self.symbolSize)
                    .tag(1)
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

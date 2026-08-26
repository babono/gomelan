//
//  WelcomeView.swift
//  Kotek
//
//  Entry screen (PRD §8), built to the Kotek design: the wordmark over the
//  drifting pattern, one cream key to press, and a pelawah rising from the
//  bottom edge.
//
//  The carved ornaments that used to drift down both margins are held out at
//  the designer's request. `Ornaments` below is left intact and simply not
//  placed — the arrangement, the rates and the reasons they are what they are
//  took measurement to arrive at, and deleting them would mean deriving all of
//  it again if the marks come back.
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

    /// The two corner buttons are drawn to ONE size and share the chrome that
    /// makes them one.
    ///
    /// They started as whatever their contents happened to need — a logo under
    /// a caption, and a line of type — so they were different heights,
    /// different widths, and read as two unrelated things that had drifted into
    /// the same corner. A pair has to look like a pair before either of them
    /// reads as a control at all.
    ///
    /// Both stay in the CORNER rather than the column: this screen is a
    /// wordmark and one way in, and a second thing to read in the middle of it
    /// would make the way in the third thing you notice. And both are only ever
    /// opened by asking — a credit that introduces itself over the landing
    /// screen is an ad, and somebody who knows what a gamelan is should not
    /// have to dismiss an explanation of one to reach their instrument.
    private static let cornerSize = CGSize(width: 168, height: 40)

    private func cornerButton<V: View>(_ label: String,
                                       hint: String,
                                       guide: AppState.Guide,
                                       @ViewBuilder content: () -> V) -> some View {
        Button { app.openGuide(guide) } label: {
            content()
                .frame(width: Self.cornerSize.width, height: Self.cornerSize.height)
                //R The border is what makes these controls. Without one they
                //R read as exactly what they are made of — a printed colophon
                //R and a line of type — and nobody taps a colophon.
                .background(Theme.cream.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: Theme.radius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius)
                        .strokeBorder(Theme.cream.opacity(0.2), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.kajar)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }

    /// Their mark, and nothing else.
    ///
    /// "In collaboration with" is gone: it was a caption explaining a logo, and
    /// a logo in the corner of a landing screen does not need explaining — it
    /// needed a border, which it now has. Losing the line is also what lets the
    /// mark sit on one row, which is what lets the two buttons match.
    private var collaborator: some View {
        cornerButton("About Mekar Bhuana",
                     hint: "Opens a short introduction",
                     guide: .mekarBhuana) {
            Image("logo-mekarbhuana")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 22)
        }
    }

    /// The background read, for anyone who arrives not knowing what a gamelan
    /// is — and only for them.
    private var aboutGamelan: some View {
        cornerButton("About gamelan",
                     hint: "Opens a short introduction to gamelan and kotekan",
                     guide: .gamelan) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                    .font(.symbol(12, weight: .medium))
                Text("What is gamelan?")
                    .font(.sans(13))
            }
            .foregroundStyle(Theme.cream.opacity(0.72))
        }
    }


    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height

            ZStack {
                // Ornaments() — held out, see the file header.

                VStack(spacing: 0) {
                    // Geometry shared with the splash screen, not restated —
                    // the hand-over is a cross-fade around a wordmark that does
                    // not move, which only holds if both screens draw it from
                    // the same numbers. See `KotekWordmark`.
                    Spacer().frame(height: KotekWordmark.topInset(in: h))

                    KotekWordmark(width: KotekWordmark.width(in: proxy.size.width))

                    Spacer().frame(height: h * 0.07)

                    PillButton(title: "Get started", trailingSystemImage: "arrow.right", style: .filled) {
                        music.stop()
                        app.begin()
                    }
                    // No fixed width any more: at Black with 1.5pt tracking,
                    // "GET STARTED" does not fit the 146pt the one-word label
                    // used to sit in. The button sizes to its own label and its
                    // padding, which is what stops the next copy change from
                    // silently truncating it.
                    .fixedSize()

                    Spacer()
                }

                // The collaborator's mark, top trailing.
                //
                // A CORNER, not the column. The middle of this screen is a
                // wordmark, a script and one button, and that emptiness is the
                // whole design — putting a second logo into it would make the
                // landing screen a page of credits. Up here it reads as a
                // colophon: present, quiet, and obviously not the way in.
                VStack {
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            collaborator
                            aboutGamelan
                        }
                    }
                    Spacer()
                }
                .padding(.top, 14)
                .padding(.trailing, 22)

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

/// The carved ornaments behind the title: three down each side, breathing.
///
/// They hold their side of the screen, as the design shows — the centre stays
/// clear for the wordmark and the button, which is the whole reason the marks
/// live in the margins. So there is no crossing and no wrapping: each one drifts
/// slowly up and down about a fixed home, with a little horizontal sway, and
/// turns continuously.
///
/// Motion used to be derived from the clock: every position and angle a function
/// of `t`, redrawn in one `Canvas` inside a `TimelineView` at 30fps. Elegant,
/// and the second most expensive thing in the app — a full-screen canvas with
/// six rotated blits, thirty times a second, on a screen where nothing happens.
/// Measured on device it and the pattern behind it together ran GPU 54% / CPU
/// 32% with the phone simply sitting here.
///
/// Each mark is its own view now, and every motion is a `repeatForever` Core
/// Animation: the render server interpolates the transforms and the app process
/// does nothing at all per frame. `easeInOut` autoreversing is a sine to within
/// a couple of percent, which is well inside what a sixteen-point drift can
/// show.
///
/// The rates are deliberately incommensurate and the seeds are arbitrary, so the
/// six never fall into step — which is what makes it read as drifting rather
/// than pulsing. Rotation is a full turn per period, so a mark always comes back
/// to where it started and the loop is seamless however long the screen is left
/// up. Alternate marks start their drift at the opposite end of the travel,
/// which is what the old per-mark phase seed was for.
private struct Ornaments: View {
    /// One ornament, at rest on its own side of the screen.
    struct Mark: Identifiable {
        let id: Int
        let art: Int
        /// Fractions of the frame — so the arrangement survives a different
        /// aspect ratio instead of collecting in a corner.
        let x: Double
        let y: Double
        /// Points, so a mark looks the same size on every screen.
        let size: Double
        /// How far it drifts vertically, in points, and how long a round trip
        /// takes. Vertical is the dominant motion; `sway` is a fraction of it.
        let rise: Double
        let risePeriod: Double
        let sway: Double
        /// Seconds for one full turn. Negative turns anticlockwise.
        let spinPeriod: Double
        let opacity: Double
    }

    /// Three a side, mirrored loosely rather than exactly — a perfectly
    /// symmetric arrangement reads as a border rather than as scattered marks.
    private let marks: [Mark] = [
        // Left
        Mark(id: 0, art: 0, x: 0.08, y: 0.16, size: 58, rise: 16, risePeriod: 11, sway: 0.35, spinPeriod:  38, opacity: 0.50),
        Mark(id: 1, art: 1, x: 0.14, y: 0.48, size: 44, rise: 12, risePeriod:  8, sway: 0.30, spinPeriod: -29, opacity: 0.38),
        Mark(id: 2, art: 0, x: 0.06, y: 0.79, size: 66, rise: 19, risePeriod: 14, sway: 0.25, spinPeriod:  47, opacity: 0.45),
        // Right
        Mark(id: 3, art: 1, x: 0.90, y: 0.13, size: 62, rise: 18, risePeriod: 13, sway: 0.28, spinPeriod: -34, opacity: 0.46),
        Mark(id: 4, art: 0, x: 0.84, y: 0.45, size: 46, rise: 13, risePeriod:  9, sway: 0.32, spinPeriod:  26, opacity: 0.36),
        Mark(id: 5, art: 1, x: 0.92, y: 0.76, size: 54, rise: 15, risePeriod: 12, sway: 0.27, spinPeriod: -41, opacity: 0.44),
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(marks) { mark in
                DriftingMark(mark: mark, inverted: mark.id.isMultiple(of: 2))
                    .position(x: mark.x * geo.size.width,
                              y: mark.y * geo.size.height)
            }
        }
        .allowsHitTesting(false)
    }
}

/// One ornament: turning, rising and swaying, all of it on the render server.
///
/// Three separate `.animation(_:value:)` modifiers rather than one. Each only
/// responds to its own value, so the three motions keep their own periods —
/// which is the point: rise and sway run against each other so the pair traces a
/// slow wandering figure rather than a straight diagonal back and forth.
private struct DriftingMark: View {
    let mark: Ornaments.Mark
    /// Start this one at the far end of its travel, so neighbours with similar
    /// periods do not set off together.
    let inverted: Bool

    @State private var spun = false
    @State private var risen = false
    @State private var swayed = false

    private var art: String { mark.art == 0 ? "ornament-1" : "ornament-2" }
    private var direction: Double { inverted ? -1 : 1 }
    private var swayBy: Double { mark.rise * mark.sway }

    var body: some View {
        Image(art)
            .resizable()
            .frame(width: mark.size, height: mark.size)
            .opacity(mark.opacity)
            .rotationEffect(.degrees(spun ? (mark.spinPeriod < 0 ? -360 : 360) : 0))
            .animation(.linear(duration: abs(mark.spinPeriod))
                        .repeatForever(autoreverses: false), value: spun)
            .offset(y: (risen ? mark.rise : -mark.rise) * direction)
            //R Half the period: one leg of an autoreversing animation is half a
            //R round trip, and `risePeriod` has always meant the round trip.
            .animation(.easeInOut(duration: mark.risePeriod / 2)
                        .repeatForever(autoreverses: true), value: risen)
            .offset(x: (swayed ? swayBy : -swayBy) * direction)
            .animation(.easeInOut(duration: mark.risePeriod * 1.6 / 2)
                        .repeatForever(autoreverses: true), value: swayed)
            .onAppear {
                spun = true
                risen = true
                swayed = true
            }
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
        //R 20fps, down from 30. This one cannot become a Core Animation the way
        //R the pattern and the ornaments did — the glow and the dip are decay
        //R envelopes off a hashed stroke schedule, not a transform — so the only
        //R lever is how often it repaints. It is a 470x142 strip rather than a
        //R full screen, so it was never the expensive one; a third off is free.
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
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

//
//  KipliGuide.swift
//  Kotek
//
//  Kipli, the mascot, as the app's guide (the November 2026 redesign): his
//  face and a speech bubble saying what this screen is for, or what to do
//  next. Every screen that has something to explain says it through him, in
//  his voice — first person, warm, "kamu" in Indonesian — rather than as a
//  caption nobody reads.
//
//  One component, four placements, so he is always the same character in
//  the same place:
//
//   - `.hint` — the default. Face and a one-line bubble, bottom-left of the
//     screen, where the mockups put him ("Tap your gangsa to begin.").
//   - `.intro` — larger, with a second line of detail under the bubble, for
//     an empty state where he is the whole story ("Let's set up your gangsa
//     together.").
//   - `.quiet` — a small face for a screen that needs the room (the kotekan
//     picker, in the gap under its header; the waterfall's top-left corner,
//     in Learn and free play; Learn's Watch, over the stage's top-left under
//     the lane pills). He says his line as the screen
//     opens — the bubble opens at his RIGHT, over the layout rather than in
//     it, so nothing shifts when it closes — then closes it after a few
//     seconds; tapping him opens it again. He was first in the picker's
//     bottom row, the bubble popping up above him, where the filter pills
//     drawn after him covered it; then among the header's controls with it
//     dropping below, where it covered the subtitle and the centred card.
//     Every new line opens the bubble again.
//     On the waterfall he first stood at the bottom-left, beside the gangsa
//     (or on it), his bubble opening above him (`.aside`) — down where the
//     eye is on the notes landing. Moved to the top-left, out of the way.
//   - `.flying` — Learn's Watch, where there is nothing to play and he can
//     have the stage: the small face drifting about its top over both
//     gangsa, bobbing as he hovers, the bubble dropping below him wherever
//     he is. He holds still while he talks, so the words never slide away
//     from the eye, and flies on once the bubble closes. Watch had a `.drop`
//     first — the face in the header beside the step strip, the bubble
//     dropping onto the stage — then a `.quiet` one parked at the stage's
//     top-left; both read as part of the layout, not a guide over it.
//
//  He speaks in the OUTLINED bubble, as the design system has it: white,
//  ringed in Ireng, standing on a Garis edge like the buttons. The words type
//  themselves out, left to right, as if he were saying them: `Typewriter`
//  draws the laid-out text a glyph at a time, so the bubble is its full size
//  from the first frame and only the letters arrive — growing the bubble
//  with a string's prefix would have wobbled it, and could not take a
//  `LocalizedStringKey` apart anyway.
//
//  He has moods (the designer's faces, November 2026): happy — the default,
//  and whenever things are going well — sad, and angry. Each is two frames,
//  mouth shut and open, and he flaps between them for as long as the words
//  take to type out (`KipliFace`), so he is seen to say them. It replaced one
//  still face (`kipli-guide`).
//

import SwiftUI

struct KipliGuide: View {
    enum Style { case hint, intro, quiet, flying }

    enum Mood { case happy, sad, angry }

    /// A resource rather than a `LocalizedStringKey`: it can be resolved to
    /// count its letters, which is how long he talks for.
    let message: LocalizedStringResource
    /// The second line under the bubble — `.intro` only.
    var detail: LocalizedStringKey?
    var style = Style.hint
    var mood = Mood.happy

    @State private var speaking = true
    /// Bumped each time he starts a line: restarts the talking and, for the
    /// styles that close themselves, the timer that closes the bubble.
    @State private var said = 0
    @State private var talking = false
    /// `.flying`: seconds of flight before the leg under way, and when that
    /// leg began (nil while he is talking). His place is a function of the
    /// flight time, so stopping the clock stops him exactly where he is —
    /// an animation to a waypoint could only be cut short with a jump.
    @State private var flown: Double = 0
    @State private var legStarted: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long a `.quiet` Kipli keeps his bubble open on his own,
    /// after he has finished saying it.
    private static let quietFor: Duration = .seconds(5)

    private var closesItself: Bool {
        style == .quiet || style == .flying
    }

    /// The line as it reads, for counting and for noticing a new one.
    private var spoken: String {
        String(localized: message)
    }

    private var faceHeight: CGFloat {
        switch style {
        case .intro: 66
        case .hint: 52
        case .quiet, .flying: 40
        }
    }

    var body: some View {
        placed
            // One element: "Kipli says: …". The face alone means nothing read out.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Kipli says: \(Text(message))"))
            // Talk for as long as the words take to type, then — the styles
            // that close themselves — leave the line up a while and close it.
            // Restarted (cancelled and run again) by every new line; a cancelled
            // run changes nothing, or a new line would be closed by the old one.
            .task(id: said) {
                talking = !reduceMotion
                do {
                    try await Task.sleep(for: .seconds(Typewriter.duration(of: spoken.count)))
                    talking = false
                    guard closesItself else { return }
                    try await Task.sleep(for: Self.quietFor)
                } catch {
                    return
                }
                withAnimation(.easeInOut(duration: 0.25)) { speaking = false }
            }
            // A new line from him opens the bubble again.
            .onChange(of: spoken) {
                withAnimation(.easeInOut(duration: 0.2)) { speaking = true }
                said += 1
            }
            // `.flying`: the flight clock runs only while he is quiet.
            .onChange(of: speaking) { _, now in
                let t = Date.timeIntervalSinceReferenceDate
                if now {
                    flown += legStarted.map { t - $0 } ?? 0
                    legStarted = nil
                } else {
                    legStarted = t
                }
            }
    }

    @ViewBuilder
    private var placed: some View {
        if style == .flying {
            flight
        } else {
            laidOut
        }
    }

    private var laidOut: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                if style == .quiet {
                    face
                        .overlay(alignment: .leading) {
                            if speaking {
                                bubble
                                    .fixedSize()
                                    // 10pt off his cheek. An offset, not an
                                    // alignment guide: a guide was ignored on
                                    // iPad and the bubble sat on his face.
                                    .offset(x: faceHeight * KipliFace.aspect + 10)
                                    .transition(pop(from: .leading))
                            }
                        }
                } else {
                    face
                    bubble
                }
            }
            if style == .intro, let detail {
                Text(detail)
                    .font(.sans(15))
                    .foregroundStyle(Theme.description)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, faceHeight * KipliFace.aspect + 14)
            }
        }
    }

    // MARK: Flying

    /// `.flying`: over the whole of what it is laid over, the face wandering
    /// its top and the bubble dropping below him. A slow figure of eight —
    /// two eased swings, side to side over 34 s and up and down over 13 —
    /// that starts in the top-left corner, where he says his first line.
    /// Any faster and he darted; the eye followed him instead of the notes.
    private var flight: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: reduceMotion)) { context in
                let now = context.date.timeIntervalSinceReferenceDate
                let t = reduceMotion ? 0 : flown + (legStarted.map { now - $0 } ?? 0)
                let faceWidth = faceHeight * KipliFace.aspect
                let roamX = max(0, geo.size.width - faceWidth)
                // The upper part only, with room under him for the bubble.
                let roamY = max(0, min(geo.size.height * 0.35, geo.size.height - faceHeight - 150))
                let x = roamX * (0.5 - 0.5 * cos(2 * .pi * t / 34))
                let y = roamY * (0.5 - 0.5 * cos(2 * .pi * t / 13))
                // The hover: a bob and a slight rock, always — even while he
                // talks — on its own clock, so he never hangs dead still.
                let bob = reduceMotion ? 0 : sin(2 * .pi * now / 2.2)
                let bubbleWidth = min(Self.flyingBubbleWidth, geo.size.width)
                ZStack(alignment: .topLeading) {
                    face
                        .rotationEffect(.degrees(3 * bob))
                        .offset(x: x, y: y + 4 * bob)
                    if speaking {
                        bubble
                            .frame(width: bubbleWidth, alignment: .leading)
                            // Under him, kept on the screen at the edges.
                            .offset(
                                x: min(max(0, x - 8), geo.size.width - bubbleWidth),
                                y: y + faceHeight + 10
                            )
                            .transition(pop(from: .topLeading))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
    }

    /// Wide enough for two lines of a long one; a short line keeps its own width.
    private static let flyingBubbleWidth: CGFloat = 320

    private func pop(from anchor: UnitPoint) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: anchor))
    }

    private var face: some View {
        KipliFace(mood: mood, height: faceHeight, talking: talking && speaking)
            .contentShape(Rectangle())
            .onTapGesture {
                guard closesItself else { return }
                KajarTick.strike()
                withAnimation(.easeInOut(duration: 0.2)) { speaking.toggle() }
                if speaking { said += 1 }
            }
            .accessibilityHidden(true)
    }

    private var bubble: some View {
        SpokenText(message: message)
            .font(.sans(style == .intro ? 16 : 15))
            .foregroundStyle(Theme.cream)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .tactile(
                RoundedRectangle(cornerRadius: 14),
                fill: Theme.surface,
                outline: Theme.ireng,
                outlineWidth: 1.5,
                base: Theme.hairline,
                depth: 3
            )
    }
}

/// The bubble's words, typed out each time the bubble appears or he says
/// something new. Its own view so the typing starts from the bubble's own
/// appearance: a `.quiet` bubble is inserted afresh each time it opens, and a
/// trigger bumped in the same update as the insertion would never be seen to
/// change.
private struct SpokenText: View {
    let message: LocalizedStringResource
    @State private var said = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(message)
            .keyframeAnimator(initialValue: reduceMotion ? Typewriter.longest : 0, trigger: said) { text, elapsed in
                text.textRenderer(Typewriter(elapsed: elapsed))
            } keyframes: { _ in
                LinearKeyframe(Typewriter.longest, duration: reduceMotion ? 0 : Typewriter.longest)
            }
            .onAppear { said += 1 }
            .onChange(of: String(localized: message)) { said += 1 }
    }
}

/// Draws the first glyphs of the laid-out text, as many as `elapsed` seconds
/// of typing would have reached: 35 a second, a speaking pace, but never
/// slower than finishing in `longest` — a long line speeds up rather than
/// keeping him talking after he would have stopped.
private struct Typewriter: TextRenderer {
    var elapsed: Double

    static let longest = 2.5
    private static let perSecond = 35.0

    /// Seconds to type a line this long — when the last glyph lands.
    static func duration(of glyphs: Int) -> Double {
        min(longest, Double(glyphs) / perSecond)
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let total = layout.reduce(0) { $0 + $1.reduce(0) { $0 + $1.count } }
        let shown = max(elapsed * Self.perSecond, Double(total) * elapsed / Self.longest)
        var drawn = 0.0
        for line in layout {
            for run in line {
                for glyph in run {
                    guard drawn < shown else { return }
                    ctx.draw(glyph)
                    drawn += 1
                }
            }
        }
    }
}

/// Kipli's face in a mood, his mouth working while `talking`: the designer's
/// two frames for each mood, shut and open, swapped a few times a second.
/// The open frame is the same face with the jaw dropped — taller, from the
/// same top — so both are drawn from the top of the box and the jaw hangs
/// below it, rather than the face jumping as it is fitted to its height.
struct KipliFace: View {
    var mood = KipliGuide.Mood.happy
    let height: CGFloat
    var talking = false

    /// The shut faces' proportions (389 x 341).
    static let aspect: CGFloat = 389.0 / 341.0
    /// Seconds per frame of the flap: a syllable's pace.
    private static let flap = 0.13

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.flap, paused: !talking)) { context in
            let open = talking && Int(context.date.timeIntervalSinceReferenceDate / Self.flap) % 2 == 0
            Image(open ? "\(name)-open" : name)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: height * Self.aspect)
                .frame(width: height * Self.aspect, height: height, alignment: .top)
        }
        .accessibilityHidden(true)
    }

    private var name: String {
        switch mood {
        case .happy: "kipli-happy"
        case .sad: "kipli-sad"
        case .angry: "kipli-angry"
        }
    }
}

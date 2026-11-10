//
//  OnboardingArt.swift
//  Kotek
//
//  The three slides' pictures, the designer's November 2026 onboarding
//  (02c Onboarding 1–3), each animated. Everything moving is a pure function
//  of the clock, as in `GangsaTable` and `SensorGuideView`: one Canvas pass,
//  no per-key views, nothing stored that could drift.
//
//  The artwork is SVG from the designer, drawn at its own units and scaled to
//  fit; what moves on it (the bilah, the mallet, the little waterfall) is drawn
//  here in the same units, read off the mockups.
//

import FactoryKit
import SwiftUI

// MARK: - Slide 1: the nawa sanga mark

/// The logo's eight mallets, lit one at a time round the rose while it turns.
///
/// The designer drew it as eight frames, one petal lit in each. It is one SVG
/// split in two instead (`scripts/split-onboarding-mark.py`, from
/// `logo-baru.svg`): `onboarding-mark` with every petal unlit, and an overlay
/// per petal in its lit colours (white rim, gold face, white glyph),
/// `onboarding-mark-lit-0…7` in the frames' order — north-east first, then on
/// round anticlockwise. Eight whole frames would swap at a step; overlays can
/// cross-fade, and the rose turns under them as one piece.
struct NawaSangaMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds each petal holds the light.
    private static let step = 0.5
    /// How long a petal takes to light, and to let go: they overlap, so the
    /// light runs round rather than jumping.
    private static let fadeIn = 0.12
    private static let fadeOut = 0.25
    /// One slow turn, as the splash's rose and the website's.
    private static let turn = 60.0

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Image("onboarding-mark").resizable()
                ForEach(0 ..< 8, id: \.self) { petal in
                    Image("onboarding-mark-lit-\(petal)")
                        .resizable()
                        .opacity(light(petal, at: t))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: Self.turn) / Self.turn * 360))
        }
        // The mockup's mark is about half the slide's height.
        .padding(36)
    }

    /// 0…1: up over `fadeIn` when its turn comes, down over `fadeOut` once
    /// the next has it.
    private func light(_ petal: Int, at t: Double) -> Double {
        let lap = 8 * Self.step
        // Seconds since this petal's turn began, 0..<lap.
        let since = (t - Double(petal) * Self.step).truncatingRemainder(dividingBy: lap)
        let age = since < 0 ? since + lap : since
        if age < Self.step { return min(1, age / Self.fadeIn) }
        return max(0, 1 - (age - Self.step) / Self.fadeOut)
    }
}

// MARK: - The landing's mallet

/// `mallet.svg`, played as the landing's gangsa plays it (`GangsaTable`):
/// drawn AT contact, the head on the bilah, and lifted by turning about the
/// end of the handle.
enum OnboardingMallet {
    static let size = CGSize(width: 153, height: 114)
    /// Where the head meets the key, in the mallet's units.
    static let strikePoint = CGPoint(x: 39.5, y: 65.5)
    /// The end of the handle.
    static let pivot = CGPoint(x: 118, y: 108)
    static let liftAngle = 16.0

    /// Draws it with the head at `point`, `scale` points to its unit.
    static func draw(_ ctx: GraphicsContext, at point: CGPoint, scale: CGFloat, angle: Double) {
        var c = ctx
        c.translateBy(x: point.x, y: point.y)
        c.scaleBy(x: scale, y: scale)
        c.translateBy(x: pivot.x - strikePoint.x, y: pivot.y - strikePoint.y)
        c.rotate(by: .degrees(angle))
        c.translateBy(x: -pivot.x, y: -pivot.y)
        c.draw(c.resolve(Image("mallet")), in: CGRect(origin: .zero, size: size))
    }

    /// `phase` of the way from one stroke (0) to the next (1): how far it has
    /// moved towards the next key, and how high it is. Contact at the
    /// stroke, a quick rebound, the move in the middle, the fall onto the
    /// next — continuous at the seam. `GangsaTable.malletPose`'s curve.
    static func pose(phase p: Double) -> (travel: CGFloat, angle: Double) {
        let travel = min(1, max(0, (p - 0.15) / 0.6))
        let eased = travel * travel * (3 - 2 * travel)
        return (CGFloat(eased), liftAngle * (1 - max(exp(-p / 0.08), pow(p, 6))))
    }
}

/// A struck bilah's light: full at the stroke, ringing away, until the next
/// stroke on the same gangsa damps it.
private func ring(since age: Double, decay: Double = 0.45) -> Double {
    age < 0 ? 0 : exp(-age / decay)
}

/// The positive remainder, for stroke counts that start below zero.
private func wrap(_ n: Int, _ m: Int) -> Int {
    ((n % m) + m) % m
}

// MARK: - Slide 2: two gangsas, the interlock

/// Polos on the gangsa behind, sangsih on the one in front, each with its own
/// mallet, playing the kotekan guide's sample (`KotekanSample`) between them.
/// It plays together, silently, until a button asks to hear a half, or both:
/// then that plays on the gangsa's sounds, twice round, as on the kotekan
/// list's "How kotekan works", and the half not asked for rests. The landing's
/// music hushes while it does (`AppState.musicHushed`).
struct InterlockArt: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hearing: GuideVoice?
    /// Slot 0. Reset when a sample starts, so the sound and the mallets agree.
    @State private var origin = Date()

    private let cue: CuePlayer = Container.shared.cueService()

    /// `gangsa-kotekan-onboarding.svg`.
    private static let frame = CGSize(width: 225, height: 110)
    /// The mockup's pair: polos up and to the right, sangsih in front.
    private static let polosOrigin = CGPoint(x: 60, y: 22)
    private static let sangsihOrigin = CGPoint(x: 0, y: 137)
    private static let art = CGSize(width: 285, height: 249)
    private static let keys = 10
    private static let malletScale: CGFloat = 0.5
    private static var stroke: Double {
        Double(KotekanSample.strokeMs) / 1000
    }

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 0.05 : timeline.date.timeIntervalSince(origin)
                VStack(spacing: 8) {
                    Canvas { ctx, size in draw(ctx, size: size, at: t) }
                        .aspectRatio(Self.art.width / Self.art.height, contentMode: .fit)
                        .accessibilityHidden(true)
                    // The notes being played, as the kotekan guide draws them:
                    // the half asked for solid, the other a dashed ghost, both
                    // together by default; the stroke sounding ringed in gold,
                    // on the mallets' clock.
                    let voice = hearing ?? .together
                    HStack(spacing: 10) {
                        Text(voice.title)
                            .font(.serif(20))
                            .foregroundStyle(voice.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        KotekanSampleRoll(
                            voice: voice,
                            slot: reduceMotion ? nil : wrap(Int(floor(t / Self.stroke)), KotekanSample.slots)
                        )
                        // Eight strokes over four bilah: 2 : 1 is square cells.
                        .frame(width: 136, height: 68)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 8)
                    .padding(.vertical, 4)
                    .background(Theme.deep, in: RoundedRectangle(cornerRadius: 14))
                    .animation(.easeOut(duration: 0.2), value: hearing)
                }
            }

            HStack(spacing: 8) {
                ForEach(GuideVoice.allCases) { voice in
                    hearButton(voice)
                }
            }
        }
        .task(id: hearing) {
            // The landing's music hushes while a sample plays, so the halves
            // are heard on their own.
            app.musicHushed = hearing != nil
            await play(hearing)
        }
        .onDisappear { app.musicHushed = false }
    }

    private func hearButton(_ voice: GuideVoice) -> some View {
        let on = hearing == voice
        return AppButton(
            title: on ? "Stop" : voice.title,
            systemImage: on ? "speaker.wave.3.fill" : "speaker.wave.2.fill",
            prominence: on ? .selected : .secondary,
            size: .compact
        ) {
            hearing = on ? nil : voice
        }
        .accessibilityLabel(on ? Text("Stop") : Text(voice.hear))
    }

    /// The sample twice round on the key sounds, polos to the left and
    /// sangsih to the right — `KotekanGuideView.play`, on this clock.
    private func play(_ voice: GuideVoice?) async {
        guard let voice else { return }
        let start = Date()
        origin = start
        cue.start()
        for step in 0 ..< KotekanSample.slots * 2 {
            let at = start.addingTimeInterval(Double(step) * Self.stroke)
            let wait = at.timeIntervalSinceNow
            if wait > 0 {
                do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            }
            let slot = step % KotekanSample.slots
            for half in voice.halves {
                if let key = KotekanSample.key(half, at: slot) {
                    cue.playKeySample(index: key, pan: half == .polos ? -0.3 : 0.3, volume: 0.8)
                }
            }
        }
        do { try await Task.sleep(for: .seconds(Self.stroke)) } catch { return }
        hearing = nil
    }

    // MARK: Drawing

    private func draw(_ ctx: GraphicsContext, size: CGSize, at t: Double) {
        let s = min(size.width / Self.art.width, size.height / Self.art.height)
        let o = CGPoint(x: (size.width - Self.art.width * s) / 2, y: (size.height - Self.art.height * s) / 2)
        let playing = (hearing ?? .together).halves
        // Back to front: polos behind, so sangsih's mallet passes over it.
        for half in [KotekanHalf.polos, .sangsih] {
            let at = half == .polos ? Self.polosOrigin : Self.sangsihOrigin
            let place = { (p: CGPoint) in
                CGPoint(x: o.x + (at.x + p.x) * s, y: o.y + (at.y + p.y) * s)
            }
            gangsa(ctx, half: half, place: place, scale: s, at: t, playing: playing.contains(half))
        }
    }

    /// The bilah, in the frame's units: ten slats lying across its back, seen
    /// from the front and above, so they fan out a little towards the top and
    /// shorten up the scale. Read off the mockup.
    private static func key(_ i: Int) -> [CGPoint] {
        let f = CGFloat(i)
        let top = 21 + f * 0.8
        let topX = 40 + f * 15.1
        let bottomX = 46 + f * 13.9
        return [
            CGPoint(x: topX, y: top), CGPoint(x: topX + 13, y: top),
            CGPoint(x: bottomX + 11.3, y: 64), CGPoint(x: bottomX, y: 64),
        ]
    }

    /// Where a mallet's head lands on key `i`: a third of the way down.
    private static func strikePoint(_ i: Int) -> CGPoint {
        let k = key(i)
        let top = CGPoint(x: (k[0].x + k[1].x) / 2, y: k[0].y)
        let bottom = CGPoint(x: (k[2].x + k[3].x) / 2, y: k[2].y)
        return CGPoint(x: top.x + (bottom.x - top.x) * 0.3, y: top.y + (bottom.y - top.y) * 0.3)
    }

    private func gangsa(
        _ ctx: GraphicsContext,
        half: KotekanHalf,
        place: (CGPoint) -> CGPoint,
        scale s: CGFloat,
        at t: Double,
        playing: Bool
    ) {
        let topLeft = place(.zero)
        ctx.draw(
            ctx.resolve(Image("gangsa-kotekan-onboarding")),
            in: CGRect(origin: topLeft, size: CGSize(width: Self.frame.width * s, height: Self.frame.height * s))
        )

        // This half's strokes come every other slot: polos on the even ones,
        // sangsih on the odd. Stroke j is at slot 2j + offset.
        let offset = half == .polos ? 0 : 1
        let beats = (t / Self.stroke - Double(offset)) / 2
        let j = Int(floor(beats))
        let phase = beats - Double(j)
        let keyAt = { (j: Int) in KotekanSample.line[wrap(2 * j + offset, KotekanSample.slots)] }
        let struck = keyAt(j)
        let light = playing ? ring(since: phase * 2 * Self.stroke) : 0

        for i in 0 ..< Self.keys {
            let corners = Self.key(i).map(place)
            var bar = Path()
            bar.addLines(corners)
            bar.closeSubpath()
            let face = i == struck ? Theme.bilah.mix(with: Theme.keyHighlight, by: light) : Theme.bilah
            ctx.fill(bar, with: .color(face))
            ctx.stroke(bar, with: .color(Color(hex: 0xCC7421)), lineWidth: 0.8 * s)
        }

        // Resting, it holds up over the first key it will play.
        let pose = playing ? OnboardingMallet.pose(phase: phase) : (travel: 0, angle: OnboardingMallet.liftAngle)
        let from = Self.strikePoint(struck)
        let to = Self.strikePoint(keyAt(j + 1))
        let head = CGPoint(x: from.x + (to.x - from.x) * pose.travel, y: from.y + (to.y - from.y) * pose.travel)
        OnboardingMallet.draw(ctx, at: place(head), scale: Self.malletScale * s, angle: pose.angle)
    }
}

private extension GuideVoice {
    /// The roll's label: each half in its voice colour, both in ink.
    var ink: Color {
        switch self {
        case .polos: Theme.polosVoice
        case .sangsih: Theme.sangsihVoice
        case .together: Theme.heading
        }
    }
}

// MARK: - Slide 3: the gangsa and the screen

/// The front-on gangsa with a screen over it, as the app sits on a stand: notes
/// fall down their lanes on the screen, and as each lands the mallet strikes
/// that bilah on the gangsa and both light — the screen's key in gold, the
/// real one ringing. The lanes are the gangsa's keys, left to right.
struct TrackingArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `gangsa-onboarding.svg`, under the screen.
    private static let frame = CGSize(width: 239, height: 124)
    private static let frameTop: CGFloat = 62
    private static let art = CGSize(width: 239, height: 186)
    private static let keys = 10
    /// The bilah on the frame's back, in the art's units.
    private static let keysSpan: ClosedRange<CGFloat> = 39 ... 200
    private static let keyGap: CGFloat = 1.8
    private static let keyTop: CGFloat = frameTop + 18
    private static let keyHeight: CGFloat = 17
    /// The screen, on its stand behind the gangsa.
    private static let screen = CGRect(x: 50, y: 2, width: 138, height: 62)
    private static let malletScale: CGFloat = 0.72

    /// A short line, mostly stepwise, as a kotekan's polos moves.
    private static let notes = [3, 5, 4, 6, 5, 7, 6, 4]
    private static let gap = 0.7
    /// How long a note takes to fall the screen.
    private static let fall = 1.7

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            // Reduce Motion gets a frame with notes on the way down.
            let t = reduceMotion ? 3.15 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in draw(ctx, size: size, at: t) }
        }
        .aspectRatio(Self.art.width / Self.art.height, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private static var keyWidth: CGFloat {
        (keysSpan.upperBound - keysSpan.lowerBound - keyGap * CGFloat(keys - 1)) / CGFloat(keys)
    }

    private static func keyX(_ i: Int) -> CGFloat {
        keysSpan.lowerBound + (keyWidth + keyGap) * CGFloat(i)
    }

    private static func note(_ n: Int) -> Int {
        notes[wrap(n, notes.count)]
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize, at t: Double) {
        let s = min(size.width / Self.art.width, size.height / Self.art.height)
        let o = CGPoint(x: (size.width - Self.art.width * s) / 2, y: (size.height - Self.art.height * s) / 2)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: o.x + x * s, y: o.y + y * s)
        }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(origin: p(x, y), size: CGSize(width: w * s, height: h * s))
        }

        // Note n lands at n·gap. The last to land, and how long ago.
        let beats = t / Self.gap
        let n = Int(floor(beats))
        let phase = beats - Double(n)
        let struck = Self.note(n)
        let light = ring(since: phase * Self.gap)

        screen(ctx, r: r, at: t, struck: struck, light: light, scale: s)

        ctx.draw(
            ctx.resolve(Image("gangsa-onboarding")),
            in: r(0, Self.frameTop, Self.frame.width, Self.frame.height)
        )
        for i in 0 ..< Self.keys {
            let bar = Path(roundedRect: r(Self.keyX(i), Self.keyTop, Self.keyWidth, Self.keyHeight), cornerRadius: 2 * s)
            let face = i == struck ? Theme.bilah.mix(with: Theme.keyHighlight, by: light) : Theme.bilah
            ctx.fill(bar, with: .color(face))
            ctx.stroke(bar, with: .color(Color(hex: 0xCC7421)), lineWidth: 0.8 * s)
        }

        let pose = OnboardingMallet.pose(phase: phase)
        let from = Self.keyX(struck), to = Self.keyX(Self.note(n + 1))
        let x = from + (to - from) * pose.travel + Self.keyWidth * 0.55
        // A shorter swing than the pair's: the screen is just above, and a
        // full lift put the head on it.
        OnboardingMallet.draw(ctx, at: p(x, Self.keyTop + 4), scale: Self.malletScale * s, angle: pose.angle * 0.55)
    }

    /// The app on the screen: the waterfall, ten lanes over a row of keys.
    private func screen(
        _ ctx: GraphicsContext,
        r: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect,
        at t: Double,
        struck: Int,
        light: Double,
        scale s: CGFloat
    ) {
        let box = Self.screen
        let bezel = Path(roundedRect: r(box.minX, box.minY, box.width, box.height), cornerRadius: 6 * s)
        ctx.fill(bezel, with: .color(Theme.ireng))
        let inner = box.insetBy(dx: 2.4, dy: 2.4)
        let glass = Path(roundedRect: r(inner.minX, inner.minY, inner.width, inner.height), cornerRadius: 4 * s)
        ctx.fill(glass, with: .color(Theme.putih))

        var c = ctx
        c.clip(to: glass)
        let lanes = Self.keys
        let pad: CGFloat = 4
        let lane = (inner.width - pad * 2) / CGFloat(lanes)
        let tileH: CGFloat = 4.5
        let hitY = inner.maxY - tileH - 2.5
        let topY = inner.minY - 8

        // The keys along the foot, the struck one in gold.
        for i in 0 ..< lanes {
            let x = inner.minX + pad + CGFloat(i) * lane
            let tile = Path(roundedRect: r(x + 0.4, hitY + 1, lane - 0.8, tileH), cornerRadius: 1 * s)
            let face = i == struck ? Theme.bilah.mix(with: Theme.gold, by: light) : Theme.bilah.opacity(0.55)
            c.fill(tile, with: .color(face))
        }
        // The hit line.
        c.fill(Path(r(inner.minX + pad, hitY, inner.width - pad * 2, 0.5)), with: .color(Theme.hairline))
        // The struck lane glows up from the line.
        if light > 0.01 {
            let x = inner.minX + pad + CGFloat(struck) * lane
            c.fill(
                Path(r(x, hitY - 14, lane, 14)),
                with: .linearGradient(
                    Gradient(colors: [Theme.gold.opacity(0), Theme.gold.opacity(0.45 * light)]),
                    startPoint: r(x, hitY - 14, 0, 0).origin,
                    endPoint: r(x, hitY, 0, 0).origin
                )
            )
        }

        // Each note: the stroke pill, in polos red, with its stem trailing
        // above in cream, outlined, as the waterfall draws them.
        let first = Int(floor(t / Self.gap))
        for n in first ... first + Int(ceil(Self.fall / Self.gap)) + 1 {
            let lands = Double(n) * Self.gap
            let ahead = lands - t
            guard ahead > -0.05, ahead < Self.fall else { continue }
            let y = hitY - CGFloat(ahead / Self.fall) * (hitY - topY)
            let x = inner.minX + pad + CGFloat(Self.note(n)) * lane
            let w = lane * 0.62
            let stem = Path(roundedRect: r(x + (lane - w) / 2, y - 8, w, 8), cornerRadius: 1 * s)
            c.fill(stem, with: .color(Theme.surface))
            c.stroke(stem, with: .color(Theme.hairline), lineWidth: 0.5 * s)
            let head = Path(roundedRect: r(x + (lane - w) / 2, y - 2.6, w, 2.6), cornerRadius: 1.3 * s)
            c.fill(head, with: .color(Theme.polosVoice))
        }
    }
}

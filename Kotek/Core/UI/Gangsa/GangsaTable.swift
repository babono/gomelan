//
//  GangsaTable.swift
//  Kotek
//
//  The redesign's gangsa: along the foot of the landing screen, and standing
//  still on a gangsa card that has no photo. The designers' frame
//  (`gangsa-table.svg`) with the bilah drawn on it in code, playing a kotekan
//  by themselves, and the mallet (`mallet.svg`) travelling to each key as it
//  lights. It replaced `Pelawah`, the carved frame drawn entirely in code.
//
//  The November 2026 redesign redrew both files — an orange frame with gold
//  horns, a mallet with a pick-shaped head — and the frame runs off the
//  bottom of the screen: the artwork's viewBox stops at the rail, so the
//  body below it is never drawn. The motion is the brown design's, unchanged.
//
//  On a gangsa card with no photo it is drawn WHOLE (`full`): the designer's
//  `gangsa-full`, the same frame carried on down past the rail to its feet,
//  so a card shows a gangsa standing rather than its top cut off. Its top 84
//  units are `gangsa-table` exactly, so the keys and the mallet sit on it
//  at the same coordinates.
//
//  The keys are code, not artwork, because they move: each lights up and dips
//  as it is struck. Everything is a pure function of the clock — see
//  `struckBar` — so any two copies show the same frame.
//

import SwiftUI

struct GangsaTable: View {
    var keyCount = 10
    /// Whether the bilah play themselves.
    var animated = true
    /// The whole frame, down to its feet (`gangsa-full`), rather than the
    /// top that the landing screen runs off its bottom edge.
    var full = false

    /// The artwork's own units — `gangsa-table.svg` is 474 x 84, and the
    /// geometry below is read off the landing mockup, where it is drawn at 1x,
    /// so the keys land where the designer put them.
    private static let tableSize = CGSize(width: 474, height: 84)
    /// `gangsa-full.svg`: the same width, down to the feet.
    private static let fullHeight: CGFloat = 245
    /// Inside the frame's body (72…402), less the design's margin. The mockup
    /// draws nine square keys here; a gangsa pemade has ten, so ten share the
    /// same span at the same gap and come out a little narrower.
    private static let keysSpan: ClosedRange<CGFloat> = 82.5 ... 391.5
    private static let keyGap: CGFloat = 4
    private static let keyHeight: CGFloat = 31
    /// The top edge of the bilah, in the frame's units: they stand proud of
    /// the frame's back, above the rail.
    private static let keyTopOnTable: CGFloat = 35.5
    /// How far the mallet reaches above the frame, in the same units: its
    /// top at rest, in the mockup. The swing lifts the head a few points more.
    private static let malletRise: CGFloat = 30
    /// The top edge of the bilah.
    private static var keyTop: CGFloat {
        malletRise + keyTopOnTable
    }

    /// The frame's own height for a width — where its horns reach, below
    /// the mallet's room.
    static func frameHeight(for width: CGFloat) -> CGFloat {
        width / tableSize.width * tableSize.height
    }

    /// The view's height for a width: the table, plus room for the mallet.
    static func height(for width: CGFloat, full: Bool = false) -> CGFloat {
        width / tableSize.width * (artHeight(full: full) + malletRise)
    }

    private static func artHeight(full: Bool) -> CGFloat {
        full ? fullHeight : tableSize.height
    }

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / Self.tableSize.width
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !animated)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    Image(full ? "gangsa-full" : "gangsa-table")
                        .resizable()
                        .frame(width: Self.tableSize.width * s, height: Self.artHeight(full: full) * s)
                        .offset(y: Self.malletRise * s)
                    Canvas { context, _ in
                        drawKeys(context, scale: s, at: t)
                    }
                    mallet(scale: s, at: t)
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Keys

    private var keyWidth: CGFloat {
        let span = Self.keysSpan
        return (span.upperBound - span.lowerBound - Self.keyGap * CGFloat(keyCount - 1)) / CGFloat(keyCount)
    }

    /// A key's centre, in artwork units.
    private func keyCenter(_ i: Int) -> CGFloat {
        Self.keysSpan.lowerBound + (keyWidth + Self.keyGap) * CGFloat(i) + keyWidth / 2
    }

    private func drawKeys(_ context: GraphicsContext, scale s: CGFloat, at t: Double) {
        for i in 0 ..< keyCount {
            let state = animated ? state(bar: i, at: t) : BarState()
            let rect = CGRect(
                x: (keyCenter(i) - keyWidth / 2) * s,
                y: Self.keyTop * s + state.dip,
                width: keyWidth * s,
                height: Self.keyHeight * s
            )
            let shape = RoundedRectangle(cornerRadius: 3 * s).path(in: rect)
            let face = if state.glow > 0 {
                Theme.bilah.mix(with: Theme.keyHighlight, by: state.glow)
            } else if state.damp > 0 {
                Theme.bilah.mix(with: Theme.keyDampened, by: state.damp)
            } else {
                Theme.bilah
            }
            context.fill(shape, with: .color(face))
        }
    }

    // MARK: - Mallet

    /// `mallet.svg`'s own size.
    private static let malletSize = CGSize(width: 153, height: 114)
    /// Where the head meets the key, in `mallet.svg`'s units. The new
    /// artwork is drawn AT contact — the mockup's mallet rests on a key
    /// unrotated — so this is read straight off it, and the swing LIFTS the
    /// head (`liftAngle`, about the end of the handle) rather than bringing
    /// it down as the brown design's did.
    private static let strikePoint = CGPoint(x: 39.5, y: 65.5)
    private static let pivot = UnitPoint(x: 118.0 / 153.0, y: 108.0 / 114.0)
    private static let liftAngle = 16.0

    /// The mallet plays the keys: it lands on each one as it lights, and
    /// travels to the next between strokes. Same clock as the keys, so the
    /// two can never disagree about which bar was struck.
    private func mallet(scale s: CGFloat, at t: Double) -> some View {
        let (x, angle) = malletPose(at: t)
        let keyTop = Self.keyTop
        return Image("mallet")
            .resizable()
            .frame(width: Self.malletSize.width * s, height: Self.malletSize.height * s)
            .rotationEffect(.degrees(angle), anchor: Self.pivot)
            .offset(x: (x - Self.strikePoint.x) * s, y: (keyTop - Self.strikePoint.y) * s)
    }

    /// The head's x over the table, and the swing. Contact is AT each stroke,
    /// then a quick rebound, the move to the next key in the middle of the
    /// gap, and the fall onto it — continuous at the seam, so nothing jumps.
    private func malletPose(at t: Double) -> (x: CGFloat, angle: Double) {
        guard animated else { return (keyCenter(keyCount - 2), 0) }
        let n = Int(floor(t / stroke))
        let p = t / stroke - Double(n)
        let from = keyCenter(struckBar(stroke: n))
        let to = keyCenter(struckBar(stroke: n + 1))
        let travel = min(1, max(0, (p - 0.15) / 0.6))
        let eased = travel * travel * (3 - 2 * travel)
        let x = from + (to - from) * CGFloat(eased)
        let angle = Self.liftAngle * (1 - max(exp(-p / 0.08), pow(p, 6)))
        return (x, angle)
    }

    // MARK: - The kotekan the keys play

    // Deliberately not random. Random strikes across ten bars look like a fault;
    // what a gangsa actually does is kotekan — two hands alternating strokes
    // within a narrow window of adjacent keys, which is the interlock the whole
    // app is about. So the home screen quietly plays one: even strokes belong to
    // one voice and odd strokes to the other, both drawn from a four-bar window
    // that moves every few seconds.
    //
    // The whole thing is a pure function of the clock. Which bar is struck on
    // stroke N comes from hashing N, so nothing is stored, nothing drifts out of
    // sync, and the row can be drawn in one Canvas pass with no per-bar views to
    // diff. Bronze rings for about a second after it is hit, so the glow decays
    // rather than switching — until the next stroke, when the free hand stops
    // it, as a gangsa player damps each key as they strike the next. A damped
    // bar goes dull (`Theme.keyDampened`) and eases back to bronze.

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
    /// How long a damped bar takes to brighten back to bronze. It holds
    /// dull for most of a stroke first, so the damp reads as a beat of its
    /// own rather than a flicker.
    private let dampFade = 0.45

    /// How lit a bar is, how far it has been pushed down, and how dull it is
    /// from being damped.
    private struct BarState {
        var glow: Double = 0
        var dip: CGFloat = 0
        var damp: Double = 0
    }

    /// Both derived from the age of the most recent strike on this bar.
    private func state(bar: Int, at t: Double) -> BarState {
        let currentStroke = Int(floor(t / stroke))
        for back in 0 ... lookback {
            let n = currentStroke - back
            guard n >= 0, struckBar(stroke: n) == bar else { continue }
            let age = t - Double(n) * stroke // most recent hit wins
            let dip = maxDip * CGFloat(exp(-age / dipDecay))
            guard back > 0 else { return BarState(glow: max(0, 1 - age / decay), dip: dip) }
            // Damped the moment the next stroke landed.
            let since = age - stroke
            return BarState(dip: dip, damp: max(0, 1 - pow(since / dampFade, 2)))
        }
        return BarState()
    }

    /// Which bar the Nth stroke lands on.
    private func struckBar(stroke n: Int) -> Int {
        guard keyCount > 4 else { return n % max(keyCount, 1) }
        // The window wanders every 16 strokes, so the figure moves up and down
        // the instrument instead of sitting in one place.
        let span = keyCount - 3
        let window = Int(Self.hash(n / 16) % UInt64(span))
        // Even strokes to one voice, odd to the other — offset so the two
        // interleave rather than doubling each other.
        let offsets = n.isMultiple(of: 2) ? [0, 2] : [1, 3]
        let pick = offsets[Int(Self.hash(n &+ 977) % 2)]
        return min(keyCount - 1, window + pick)
    }

    /// splitmix64 — a cheap, well-mixed integer hash. Deterministic, so the
    /// same stroke always lands on the same bar however often it is redrawn.
    private static func hash(_ x: Int) -> UInt64 {
        var h = UInt64(bitPattern: Int64(x)) &+ 0x9E37_79B9_7F4A_7C15
        h = (h ^ (h >> 30)) &* 0xBF58_476D_1CE4_E5B9
        h = (h ^ (h >> 27)) &* 0x94D0_49BB_1331_11EB
        return h ^ (h >> 31)
    }
}

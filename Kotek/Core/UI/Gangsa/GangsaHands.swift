//
//  GangsaHands.swift
//  Kotek
//
//  The player's two hands on the drawn gangsa: the left pinches a bar to damp
//  it, the right swings the panggul onto the next one (§5.5). Drawn into the
//  instrument's Canvas, from the design team's art (`play-hand`, `play-finger`,
//  `play-mallet`).
//
//  The damp art is one drawing in two poses — the finger upright on the bar
//  (pinched) and the same finger turned 28.9° about a joint in the palm (open).
//  Measured off the two reference SVGs, so the swing is a rotation of one
//  image and not a cross-fade between two.
//
//  Art is placed in its own units, where the bar is 44.18 wide, so the hands
//  scale with the lane like everything else on the instrument.
//

import SwiftUI

enum GangsaHands {
    /// The longest a hand takes to cross to its next bar, in ms. Over a short
    /// gap it takes the gap.
    static let travelMs = 320.0

    // MARK: - Damp

    /// The palm. Behind the bars, as in the drawing, so it goes down before
    /// them — only a sliver beside the bar and the heel below show.
    static func palm(_ ctx: GraphicsContext, bar: CGRect, pinch: CGFloat) {
        var c = artSpace(ctx, bar: bar)
        c.translateBy(x: 0, y: (1 - pinch) * restDrop)
        c.draw(c.resolve(Image("play-hand")), in: CGRect(x: 0, y: 44.9, width: 58, height: 81))
    }

    /// The thumb, over the bar: held open and low while it travels, then
    /// rising and turning onto the bar as `pinch` goes to 1.
    static func thumb(_ ctx: GraphicsContext, bar: CGRect, pinch: CGFloat, reduceMotion: Bool) {
        var c = artSpace(ctx, bar: bar)
        c.translateBy(x: 0, y: (1 - pinch) * restDrop)
        let pivot = CGPoint(x: 14.8, y: 87.5)
        c.translateBy(x: pivot.x, y: pivot.y)
        c.rotate(by: .degrees(reduceMotion ? 0 : 28.9 * (1 - pinch)))
        c.translateBy(x: -pivot.x, y: -pivot.y)
        c.draw(c.resolve(Image("play-finger")), in: CGRect(x: 20, y: 38, width: 35, height: 66))
    }

    /// How far below the bar the open hand waits, in art units.
    private static let restDrop: CGFloat = 0

    /// The reference artboard laid over a bar, lifted: half the gangsa hangs
    /// off the bottom of the screen, so the art's own spot on the bar would be
    /// down there with it.
    private static func artSpace(_ ctx: GraphicsContext, bar: CGRect) -> GraphicsContext {
        var c = ctx
        let s = bar.width / 44.18
        c.translateBy(x: bar.midX - 33.83 * s, y: bar.minY - handLift * s)
        c.scaleBy(x: s, y: s)
        return c
    }

    /// Art units.
    private static let handLift: CGFloat = 10

    // MARK: - Mallet

    /// The panggul: `lift` 0 is the round end of the head down on the bar at
    /// the number, 1 raised. The stage carries it from bar to bar; this only
    /// draws it where it is.
    ///
    /// It strikes with the thick round end, not the middle of the head, and
    /// lands turned 20° back from the art, so the thin tail trails out over the
    /// gap as in the design team's frames. Raising it swings the whole mallet
    /// clockwise about where the hand holds the handle, so the head lifts away
    /// to the right and comes back down onto its bar, instead of sliding
    /// sideways onto the wrong one.
    ///
    /// It casts a shadow on the bars that tells how high the head is: well
    /// off to the lower left and soft while it is up, closing in and sharpening
    /// as it comes down, and gone at contact — the head is on the bar, so there
    /// is nowhere for a shadow to fall. Watching the head meet its shadow is
    /// how you see the stroke land, the way you would on a real gangsa.
    static func mallet(
        _ ctx: GraphicsContext,
        bar: CGRect,
        lift: Double,
        strikeAge: Double?,
        reduceMotion: Bool
    ) {
        let unit = bar.width / 44.18
        let s = unit * malletScale
        let cap = CGPoint(x: 17, y: 10) // art: centre of the head's round end
        let grip = CGPoint(x: 16, y: 60) // art: about where a hand holds the handle
        let landing = CGPoint(x: bar.midX + bar.width * 0.11, y: bar.minY + strikeDepth * unit)
        let seated = CGAffineTransform(translationX: landing.x, y: landing.y)
            .rotated(by: -20 * .pi / 180)
            .scaledBy(x: s, y: s)
            .translatedBy(x: -cap.x, y: -cap.y)
        let pivot = grip.applying(seated)

        var c = ctx
        if !reduceMotion, lift > 0 {
            // Added before any transform, so the offset is in screen space
            // and the light stays put while the mallet swings.
            let h = CGFloat(lift)
            let near = min(1, h / 0.12) // fades out over the last of the fall
            c.addFilter(.shadow(
                color: Color(hex: 0x140D09, alpha: 0.5 * near * (1 - 0.35 * h)),
                radius: unit * (0.6 + 6 * h),
                x: -unit * 9 * h,
                y: unit * 13 * h
            ))
        }
        c.translateBy(x: pivot.x, y: pivot.y)
        let rebound = reduceMotion ? 0 : strikeAge.map(Self.rebound) ?? 0
        c.rotate(by: .degrees(reduceMotion ? 0 : windUp * lift + rebound))
        c.translateBy(x: -pivot.x, y: -pivot.y)
        c.concatenate(seated)
        c.draw(c.resolve(Image("play-mallet")), in: CGRect(x: 0, y: 0, width: 61, height: 121))
    }

    /// Raised angle in degrees, at `lift` 1.
    private static let windUp = 30.0

    /// How high the mallet is, 0…`peak`, `phase` of the way from one stroke
    /// (0) to the next (1), `gapMs` apart.
    ///
    /// Up fast and easing out over the first 40%, a hang at the top, then
    /// thrown down along a cubic Bézier that is still steepening when it
    /// reaches the bar — the head arrives at full speed, as a struck panggul
    /// does, so contact is a sharp moment and not a settle. Fast figures lift
    /// less: there is no time for a full swing between close strokes.
    static func strokeLift(phase: Double, gapMs: Double) -> Double {
        let peak = 0.7 * min(1, max(0.35, gapMs / 450))
        let top = 0.4
        let p = min(max(phase, 0), 1)
        if p < top { return peak * UnitCurve.easeOut.value(at: p / top) }
        return peak * (1 - throwDown.value(at: (p - top) / (1 - top)))
    }

    /// Slow off the top, accelerating all the way down: it ends at a slope of
    /// ~3.7, against 0 at the start.
    private static let throwDown = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.5, y: 0),
        endControlPoint: UnitPoint(x: 0.85, y: 0.45)
    )

    /// The kick back off the bar at contact, in degrees, `age` seconds after
    /// it: a couple of quick bounces, always away from the bar — a mallet
    /// cannot go through bronze — dying away in about a tenth of a second,
    /// alongside the bar's own ring.
    /// Pure maths, called from the `Canvas` renderer, which is nonisolated.
    private nonisolated static func rebound(age: Double) -> Double {
        guard age >= 0 else { return 0 }
        return 5 * abs(sin(2 * .pi * 12 * age)) * exp(-age / 0.045)
    }

    /// Against the art's own scale. 0.75 read as a toy beside the bar.
    private static let malletScale: CGFloat = 1.1
    /// Where the round end lands, down the bar from its top, in art units:
    /// the middle of the tile, a little below its number, which sits above
    /// (`GangsaView.drawBar`). It was 40.2, the number's old place low on the
    /// tile, and read as the bar's bottom rather than its middle.
    private static let strikeDepth: CGFloat = 32
}

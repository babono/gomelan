//
//  DampGlyph.swift
//  Kotek
//
//  The damp mark: a hand seen from the side, thumb laid along the top and the
//  curled index finger meeting it at the tip — the closed pinch a gangsa
//  player stops a ringing bar with (§5.5).
//
//  Drawn, not an SF Symbol. `hand.pinch` is two fingertips meeting in the air
//  from the front, which reads as a zoom gesture. This is line art in the
//  style of the reference the team picked: the back of the hand rising from
//  the wrist into the thumb, the index finger as a loop beneath it, the other
//  fingers tucked in, and the palm edge falling back to the wrist. Drawn on
//  the falling damp cue; the bar itself just dims and shrinks.
//

import SwiftUI

enum DampGlyph {
    /// Draws the glyph filling `rect` (best at about 4:5, width:height).
    static func draw(in ctx: GraphicsContext, rect: CGRect, color: Color) {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        let line = StrokeStyle(
            lineWidth: max(1.2, rect.width * 0.075),
            lineCap: .round,
            lineJoin: .round
        )

        // Back of the hand up from the wrist, over into the thumb, out to its
        // tip and back along its underside.
        var hand = Path()
        hand.move(to: p(0.06, 0.97))
        hand.addLine(to: p(0.15, 0.42))
        hand.addQuadCurve(to: p(0.40, 0.14), control: p(0.17, 0.22))
        hand.addLine(to: p(0.80, 0.09))
        hand.addQuadCurve(to: p(0.80, 0.21), control: p(0.97, 0.13))
        hand.addLine(to: p(0.58, 0.25))
        ctx.stroke(hand, with: .color(color), style: line)

        // Index finger: a loop curled under the thumb, its tip touching the
        // thumb's — the pinch itself.
        var index = Path()
        index.move(to: p(0.72, 0.23))
        index.addQuadCurve(to: p(0.36, 0.38), control: p(0.42, 0.20))
        index.addQuadCurve(to: p(0.50, 0.47), control: p(0.34, 0.50))
        index.addQuadCurve(to: p(0.72, 0.23), control: p(0.64, 0.38))
        ctx.stroke(index, with: .color(color), style: line)

        // The other three fingers, curled into the palm: knuckles only.
        for (x, y) in [(0.72, 0.31), (0.75, 0.40), (0.70, 0.49)] {
            var knuckle = Path()
            knuckle.move(to: p(x - 0.04, y - 0.04))
            knuckle.addQuadCurve(to: p(x - 0.04, y + 0.04), control: p(x + 0.12, y))
            ctx.stroke(knuckle, with: .color(color), style: line)
        }

        // Palm edge, back down to the wrist.
        var palm = Path()
        palm.move(to: p(0.60, 0.57))
        palm.addQuadCurve(to: p(0.55, 0.74), control: p(0.60, 0.66))
        palm.addQuadCurve(to: p(0.42, 0.97), control: p(0.47, 0.84))
        ctx.stroke(palm, with: .color(color), style: line)
    }
}

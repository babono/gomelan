//
//  GangsaView.swift
//  Kotek
//
//  The instrument, drawn: two end posts and a row of flat bilah tiles. Every
//  bar the same size — the graduated lengths of a real gangsa were dropped as
//  visual noise; the numbers say low → high well enough. The bottom of the
//  view sinks off the screen (see WaterfallPlayView), so it costs less of the
//  stage. The waterfall lands just above the tiles, so both read their
//  geometry from `GangsaLayout` and a lane is exactly one bilah wide.
//
//  Proportions are the design team's drawings (`gangsa_frame.svg`,
//  `gangsa_key_default/dimmed/striked.svg`), kept in that drawing's units — a
//  bar is 110 of them wide — so the whole thing scales with the lane and the
//  frame grows with the key count. The look is the play screen of November
//  2026, which swapped those drawings' bronze bars, cord and rail for tiles.
//

import SwiftUI

/// Where every bilah sits. Shared by the waterfall and the instrument so a
/// falling note and the bar it lands on can never disagree by a pixel.
struct GangsaLayout {
    let keyCount: Int
    /// Width of the playing area — the lanes, not the frame around them.
    let width: CGFloat
    /// Tiles run on to the bottom of the view instead of stopping at their
    /// 1.25 ratio: Studio's gangsa is played, so it is as long as the room
    /// above the safe area allows, not cut off by it like the play screen's.
    var stretches = false
    /// How far the end posts run on below the view's bottom: Studio's reach
    /// the glass, past the safe area the tiles stop at. They overflow the
    /// frame, so nothing is laid out by it.
    var postBleed: CGFloat = 0

    var lane: CGFloat {
        width / CGFloat(max(1, keyCount))
    }

    /// Most of the lane, leaving a strip of the ground between bars where the
    /// cord shows through.
    var barWidth: CGFloat {
        lane * Self.barFill
    }

    /// One unit of the design drawing, where a bar is 110 wide.
    var unit: CGFloat {
        barWidth / 110
    }

    /// Wood either side of the lanes: an end post and the gap to the first bar.
    var framePad: CGFloat {
        unit * Self.framePadUnits
    }

    var frameWidth: CGFloat {
        width + framePad * 2
    }

    /// How far the end posts stand above the rail, i.e. above the view's top.
    var postRise: CGFloat {
        unit * 35.3
    }

    /// 110 of a 134-unit lane in the drawing.
    private static let barFill: CGFloat = 0.82
    private static let framePadUnits: CGFloat = 67.5

    /// The lane for a gangsa this tall — long, narrow bars; a squarer bar
    /// reads as a xylophone toy.
    static func lane(forHeight height: CGFloat) -> CGFloat {
        (height - 24) / 2.25
    }

    /// The inverse: how tall a gangsa is whose lane is `lane`.
    static func height(forLane lane: CGFloat) -> CGFloat {
        lane * 2.25 + 24
    }

    /// The lane run for `keyCount` bars at `height`, narrowed so the frame —
    /// whose posts scale with the bars — still fits in `available`.
    static func width(keyCount: Int, height: CGFloat, fitting available: CGFloat) -> CGFloat {
        let n = CGFloat(max(1, keyCount))
        let padInLanes = 2 * framePadUnits / 110 * barFill
        return max(0, min(lane(forHeight: height) * n, available * n / (n + padInLanes)))
    }

    /// How far above the waterfall's bottom edge its hit line sits, so the
    /// pads on it are drawn whole: they straddle the line, and below the edge
    /// is this view. Coop's bands read it to land on the same line.
    static let lineInset: CGFloat = 4

    /// Where the tiles hang from: the drawing's gap below the hit line, clear
    /// of it even with a halo on. Less the line's inset, which the gap used
    /// to be measured on top of — the line sat 4 pt too high over the tiles.
    var barTop: CGFloat {
        max(0, unit * 33.7 - Self.lineInset)
    }

    /// A tile is 1.25 of its width tall.
    var barHeight: CGFloat {
        barWidth * 1.25
    }

    /// How much of the instrument has to be on screen: the tiles whole, the
    /// edge under them, and a little room before the glass. What is below it
    /// — the posts' feet, the hands' wrists — can sink off the screen. It
    /// used to be a fixed half of the view, from when the bars were long
    /// bronze ones whose near ends carried nothing; that cut the tiles.
    var shownHeight: CGFloat {
        barTop + barHeight + barWidth * 0.3
    }

    func laneCenter(_ key: Int) -> CGFloat {
        (CGFloat(key) + 0.5) * lane
    }
}

/// Highlights for one bilah this frame, worked out by the caller from the
/// engine, so the instrument itself stays a pure drawing of its inputs.
struct BilahCue: Equatable {
    /// Seconds since the bar was struck, while it still shows as struck.
    /// Right or wrong is not said here — that glows in the lane above
    /// (`WaterfallCanvas`), so it can never cover the damp cue on this bar.
    var struckAge: Double?
    /// 0…1, the left hand should be pinching this bar.
    var damp: Double = 0
    /// Seconds since the pinch began, for its shiver, while it plays out.
    var dampAge: Double?
    /// The bar to strike next (Learn's Step): a dashed gold ring around it,
    /// its glow at this point of its pulse, 0…1. Nil on every other bar.
    var next: Double?
}

/// Where one of the player's hands is: on its way from bar `from` to bar
/// `to`, and how far through its stroke. Taken from the figure, not the
/// sensor, so it is a guide and works with no controller.
struct HandCue: Equatable {
    var from: Int
    var to: Int
    /// 0…1 of the way from `from` to `to`.
    var travel: Double
    /// The mallet: 0 head on the bar, 1 fully raised. The damp hand: 0 open,
    /// 1 pinched.
    var pose: Double
    /// The mallet: seconds since it last landed, for the rebound off the bar.
    var strikeAge: Double?
}

struct GangsaView: View {
    let layout: GangsaLayout
    let cues: [Int: BilahCue]
    var mallet: HandCue?
    var damper: HandCue?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var u: CGFloat {
        layout.unit
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                frame(height: geo.size.height)
                Canvas { ctx, size in
                    if let damper {
                        GangsaHands.palm(ctx, bar: handBar(damper, height: size.height), pinch: damper.pose)
                    }
                    // Struck bars last: the halo reaches into the gaps. The
                    // bar to strike next before them, so its glow is not cut
                    // by a neighbour's edge.
                    let keys = 0 ..< layout.keyCount
                    for key in keys where cues[key]?.struckAge == nil && cues[key]?.next == nil {
                        drawBar(ctx, key: key, height: size.height)
                    }
                    for key in keys where cues[key]?.struckAge == nil && cues[key]?.next != nil {
                        drawBar(ctx, key: key, height: size.height)
                    }
                    for key in keys where cues[key]?.struckAge != nil {
                        drawBar(ctx, key: key, height: size.height)
                    }
                    // Hands last, over every bar. (The palm is the exception:
                    // it is behind them, so it goes down first.)
                    if let damper {
                        GangsaHands.thumb(
                            ctx,
                            bar: handBar(damper, height: size.height),
                            pinch: damper.pose,
                            reduceMotion: reduceMotion
                        )
                    }
                    if let mallet {
                        GangsaHands.mallet(
                            ctx,
                            bar: handBar(mallet, height: size.height),
                            lift: mallet.pose,
                            strikeAge: mallet.strikeAge,
                            reduceMotion: reduceMotion
                        )
                    }
                }
                .drawingGroup()
            }
        }
    }

    // MARK: - Frame

    /// The end posts, in a soft Merah (the play redesign, November 2026).
    /// They were the landing gangsa's orange (`gangsa-table`) with a shaded
    /// strip facing the bars, and carved teak before that. There is no rail
    /// any more: the one line to hit on is the waterfall's (`WaterfallCanvas`),
    /// and a rail under it made two.
    private static let post = Color(hex: 0xE09A88)

    /// Views, not Canvas, because the posts stand above the view's top edge,
    /// which a drawing group would clip.
    private func frame(height: CGFloat) -> some View {
        let postWidth = u * 58.5
        let post = layout.stretches ? Tile.playPost : Self.post
        let shape = UnevenRoundedRectangle(topLeadingRadius: u * 16.3, topTrailingRadius: u * 16.3)
        let tall = height + layout.postRise
        // The frame sets the size the canvas beside it is laid out by, so the
        // bleed overflows it: posts taller than the frame would stretch the
        // tiles, which run to the bottom of the view, down with them.
        return HStack(alignment: .top, spacing: 0) {
            shape.fill(post).frame(width: postWidth, height: tall + layout.postBleed)
            Spacer(minLength: 0)
            shape.fill(post).frame(width: postWidth, height: tall + layout.postBleed)
        }
        .frame(width: layout.frameWidth, height: tall, alignment: .top)
        .offset(y: -layout.postRise)
    }

    // MARK: - Bars

    /// The bilah as flat tiles (the designer's play screen, November 2026):
    /// Kayu on a darker edge, the number low on the tile; struck, Merah-orange
    /// in a glowing gold ring; pinched, slate. They were bronze bars hung on
    /// a red cord — a gradient, a ridge, two pegs, a white rim when struck —
    /// long enough to run off the bottom of the screen.
    private enum Tile {
        static let fill = Color(hex: 0xF8E4B0)
        static let edge = Color(hex: 0xE7D2A2)
        static let line = Color(hex: 0xEED9A6)
        static let number = Color(hex: 0xE8B784)
        static let struck = Color(hex: 0xD4703A)
        static let damped = Color(hex: 0xBEC1CB)
        static let dampedLine = Color(hex: 0x8F93A0)
        // Studio's (`GangsaLayout.stretches`): the same hues, fuller. Nothing
        // is translucent, but the pale tile and its tan number washed out on
        // the cream canvas, and a bar you aim a finger at has to be seen.
        static let playFill = Color(hex: 0xF2CF73)
        static let playEdge = Color(hex: 0xD9B25A)
        static let playLine = Color(hex: 0xD2A94F)
        static let playNumber = Color(hex: 0xC96A2B)
        static let playPost = Color(hex: 0xDD6F55)
    }

    /// The bar a hand is over: its two bars, blended by how far along it is.
    /// Reduced motion: no glide, it is on whichever bar it is nearer.
    private func handBar(_ hand: HandCue, height: CGFloat) -> CGRect {
        let u = hand.travel
        let t = reduceMotion ? u.rounded() : u * u * (3 - 2 * u)
        var bar = barRect(hand.from, height: height)
        bar.origin.x += (barRect(hand.to, height: height).minX - bar.minX) * t
        return bar
    }

    /// A bar at rest, before any ring or pinch moves it.
    private func barRect(_ key: Int, height: CGFloat) -> CGRect {
        let w = layout.barWidth
        return CGRect(
            x: layout.framePad + layout.laneCenter(key) - w / 2,
            y: layout.barTop,
            width: w,
            // Less the edge under a tile (`drawBar`), so it is not cut.
            height: max(0, layout.stretches
                ? height - layout.barTop - w * 0.08
                : min(layout.barHeight, height - layout.barTop))
        )
    }

    private func drawBar(_ ctx: GraphicsContext, key: Int, height: CGFloat) {
        let cue = cues[key] ?? BilahCue()
        let w = layout.barWidth
        let corner = w * 0.155
        var rect = barRect(key, height: height)

        if let pulse = cue.next {
            drawNext(ctx, around: rect, pulse: reduceMotion ? 1 : pulse)
        }

        if let age = cue.struckAge {
            // Struck: the bar rings. A sideways shake that dies away fast,
            // like the bronze settling after the mallet.
            rect.origin.x += Self.ring(age: age) * w
            var ring = ctx
            ring.addFilter(.shadow(color: Theme.gold.opacity(0.75), radius: w * 0.13))
            ring.fill(
                Path(roundedRect: rect.insetBy(dx: -w * 0.045, dy: -w * 0.045), cornerRadius: corner * 1.15),
                with: .color(Theme.gold)
            )
            ctx.fill(Path(roundedRect: rect, cornerRadius: corner * 0.85), with: .color(Tile.struck))
            return
        }

        // Pinched: one last shiver that dies at once, and the tile held down
        // a hair. It used to shrink a little and go dark, the bronze falling
        // silent.
        if let age = cue.dampAge, !reduceMotion {
            rect.origin.x += 0.031 * w * sin(2 * .pi * 28 * age) * exp(-age / 0.05)
            rect.origin.y += 0.033 * w * min(1, age / 0.08)
        }
        let tile = Path(roundedRect: rect, cornerRadius: corner)
        let line = max(0.5, w * 0.022)
        let played = layout.stretches
        ctx.fill(
            Path(roundedRect: rect.offsetBy(dx: 0, dy: w * 0.078), cornerRadius: corner),
            with: .color(played ? Tile.playEdge : Tile.edge)
        )
        ctx.fill(tile, with: .color(played ? Tile.playFill : Tile.fill))
        ctx.stroke(tile, with: .color(played ? Tile.playLine : Tile.line), lineWidth: line)
        // High on the tile, above where the mallet lands
        // (`GangsaHands.strikeDepth`): a tile is played over its lower part,
        // by a finger in Studio or the mallet on the play screen, and either
        // would cover a number sitting there. It was low on the tile.
        ctx.draw(
            Text("\(key + 1)")
                .font(.system(size: max(10, w * 0.29), weight: .medium, design: .rounded))
                .foregroundStyle(played ? Tile.playNumber : Tile.number),
            at: CGPoint(x: rect.midX, y: rect.minY + w * 0.42)
        )
        // `damp` eases in and out, so the slate blends over the tile.
        if cue.damp > 0 {
            var c = ctx
            c.opacity = cue.damp
            c.fill(tile, with: .color(Tile.damped))
            c.stroke(tile, with: .color(Tile.dampedLine), lineWidth: line)
        }
    }

    /// The bar to strike next: a soft gold glow that breathes with `pulse`,
    /// under a dashed gold ring in the gap round the bar — outside the bar
    /// and its ground-coloured edge, so the bar itself is drawn as ever.
    /// The ring stays put and only the glow throbs: a blinking ring flickered,
    /// where a glow coming and going reads as calling you to it.
    private func drawNext(_ ctx: GraphicsContext, around bar: CGRect, pulse: Double) {
        let ring = Path(roundedRect: bar.insetBy(dx: -u * 9.5, dy: -u * 9.5), cornerRadius: u * 31)
        var glow = ctx
        glow.addFilter(.blur(radius: u * 12))
        glow.opacity = 0.3 + 0.7 * pulse
        glow.stroke(ring, with: .color(Theme.gold), lineWidth: u * 24)
        ctx.stroke(
            ring,
            with: .color(Theme.gold),
            style: StrokeStyle(lineWidth: u * 8, dash: [u * 14, u * 9])
        )
    }

    /// Sideways offset of a ringing bar, as a fraction of its width.
    private static func ring(age: Double) -> CGFloat {
        guard age >= 0 else { return 0 }
        return CGFloat(0.07 * sin(2 * .pi * 16 * age) * exp(-age / 0.08))
    }
}

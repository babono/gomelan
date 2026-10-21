//
//  GangsaView.swift
//  Kotek
//
//  The instrument, drawn: two end posts, a rail, and bronze bilah hung on a
//  red cord. Every bar the same size — the graduated lengths of a real gangsa
//  were dropped as visual noise; the numbers say low → high well enough. The
//  bottom of the instrument sinks off the screen (see WaterfallPlayView), so
//  it costs less of the stage. The waterfall lands on the top of the rail, so
//  both read their geometry from `GangsaLayout` and a lane is exactly one
//  bilah wide.
//
//  Proportions and colours are the design team's drawings
//  (`gangsa_frame.svg`, `gangsa_key_default/dimmed/striked.svg`), kept in
//  that drawing's units — a bar is 110 of them wide — so the whole thing
//  scales with the lane and the frame grows with the key count.
//

import SwiftUI

/// Where every bilah sits. Shared by the waterfall and the instrument so a
/// falling note and the bar it lands on can never disagree by a pixel.
struct GangsaLayout {
    let keyCount: Int
    /// Width of the playing area — the lanes, not the frame around them.
    let width: CGFloat

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

    /// The lane run for `keyCount` bars at `height`, narrowed so the frame —
    /// whose posts scale with the bars — still fits in `available`.
    static func width(keyCount: Int, height: CGFloat, fitting available: CGFloat) -> CGFloat {
        let n = CGFloat(max(1, keyCount))
        let padInLanes = 2 * framePadUnits / 110 * barFill
        return max(0, min(lane(forHeight: height) * n, available * n / (n + padInLanes)))
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
    let tilted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var u: CGFloat {
        layout.unit
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                frame(height: geo.size.height)
                Canvas { ctx, size in
                    drawCord(ctx)
                    if let damper {
                        GangsaHands.palm(ctx, bar: handBar(damper, height: size.height), pinch: damper.pose)
                    }
                    // Struck bars last: the halo reaches into the gaps.
                    let keys = 0 ..< layout.keyCount
                    for key in keys where cues[key]?.struckAge == nil {
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
            // Tilted about the TOP edge: points on the rotation axis do not
            // move, so the landing line stays exactly where the waterfall
            // ends while the near end of the instrument swings towards you.
            .rotation3DEffect(
                .degrees(tilted ? 48 : 0),
                axis: (x: 1, y: 0, z: 0),
                anchor: .top,
                perspective: 0.55
            )
            .shadow(color: .black.opacity(tilted ? 0.55 : 0), radius: 18, y: 14)
        }
    }

    // MARK: - Frame

    private static let wood = Color(hex: 0x7E4127)
    private static let woodShade = Color(hex: 0x5A2E1B)

    /// End posts and the rail. Views, not Canvas, because the posts stand
    /// above the view's top edge, which a drawing group would clip.
    private func frame(height: CGFloat) -> some View {
        let postWidth = u * 58.5
        return ZStack(alignment: .topLeading) {
            // The rail spans the lanes exactly; its top is the landing line.
            Rectangle()
                .fill(Self.wood)
                .frame(width: layout.width, height: u * 13.4)
                .offset(x: layout.framePad)
            HStack(spacing: 0) {
                post(width: postWidth, shadeOn: .trailing)
                Spacer(minLength: 0)
                post(width: postWidth, shadeOn: .leading)
            }
            .frame(width: layout.frameWidth, height: height + layout.postRise)
            .offset(y: -layout.postRise)
        }
    }

    /// The shaded strip faces the bars, as on the drawing.
    private func post(width: CGFloat, shadeOn edge: HorizontalAlignment) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: u * 16.3, topTrailingRadius: u * 16.3)
        return shape
            .fill(Self.wood)
            .overlay(alignment: Alignment(horizontal: edge, vertical: .center)) {
                Rectangle().fill(Self.woodShade).frame(width: u * 11)
            }
            .clipShape(shape)
            .frame(width: width)
    }

    /// The cord the bars hang on, centre of the first bar to centre of the
    /// last; only the bits between bars show.
    private func drawCord(_ ctx: GraphicsContext) {
        let y = barTop + u * 70
        var line = Path()
        line.move(to: CGPoint(x: layout.framePad + layout.laneCenter(0), y: y))
        line.addLine(to: CGPoint(x: layout.framePad + layout.laneCenter(layout.keyCount - 1), y: y))
        ctx.stroke(
            line,
            with: .color(Color(hex: 0x8D3021)),
            style: StrokeStyle(lineWidth: u * 12.5, lineCap: .round)
        )
    }

    // MARK: - Bars

    /// Bars hang a little below the rail, clear of it even with a halo on.
    private var barTop: CGFloat {
        u * 33.7
    }

    /// The three looks of a bar from the drawings: at rest, pinched (dimmed),
    /// and struck, which also carries a rim and a glow around the bar.
    private struct Skin {
        var top: Color
        var bottom: Color
        var ridge: Color
        var ridgeWidth: CGFloat // units
        var pegs: Color
        var number: Color
        var rim: Color = .clear
        var glow: Color = .clear

        static let rest = Skin(
            top: Color(hex: 0xC09354),
            bottom: Color(hex: 0x8E682F),
            ridge: Color(hex: 0xC2975A),
            ridgeWidth: 42.3,
            pegs: Color(hex: 0x2B211C),
            number: Color(hex: 0x72572D)
        )
        static let dimmed = Skin(
            top: Color(hex: 0x59482E),
            bottom: Color(hex: 0x59482E),
            ridge: Color(hex: 0x7B5F39),
            ridgeWidth: 42.3,
            pegs: Color(hex: 0x2B211C),
            number: Color(hex: 0x2B211C)
        )
        static let struck = Skin(
            top: Color(hex: 0xEBB164),
            bottom: Color(hex: 0xEBB164),
            ridge: Color(hex: 0xC2975A),
            ridgeWidth: 56.3,
            pegs: Color(hex: 0x2B211C),
            number: Color(hex: 0x72572D),
            rim: Color(hex: 0xFFE2B6),
            glow: Color(hex: 0xFFE2B6, alpha: 0.3)
        )
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
            y: barTop,
            width: w,
            height: max(0, height - barTop)
        )
    }

    private func drawBar(_ ctx: GraphicsContext, key: Int, height: CGFloat) {
        let cue = cues[key] ?? BilahCue()
        let w = layout.barWidth
        var rect = barRect(key, height: height)

        if let age = cue.struckAge {
            // Struck: the bar rings. A sideways shake that dies away fast,
            // like the bronze settling after the mallet.
            rect.origin.x += Self.ring(age: age) * w
            let skin = Skin.struck
            ctx.fill(
                Path(roundedRect: rect.insetBy(dx: -u * 13, dy: -u * 13), cornerRadius: u * 34.9),
                with: .color(skin.glow)
            )
            ctx.fill(
                Path(roundedRect: rect.insetBy(dx: -u * 8.3, dy: -u * 8.3), cornerRadius: u * 30.2),
                with: .color(skin.rim)
            )
            drawSkin(ctx, skin, rect: rect, key: key)
            return
        }

        // Pinched: the bar shrinks a little and goes dark, as a damped bar
        // falls silent. `damp` eases in and out, so both blend.
        let d = CGFloat(cue.damp)
        rect = CGRect(
            x: rect.minX + d * w * 0.055,
            y: rect.minY + d * u * 6,
            width: rect.width - d * w * 0.11,
            height: rect.height - d * u * 6
        )
        // The ground-coloured edge from the drawing, which also cuts the cord
        // short of each bar.
        ctx.fill(
            Path(roundedRect: rect.insetBy(dx: -u * 4.2, dy: -u * 4.2), cornerRadius: u * 26),
            with: .color(Theme.ground)
        )
        drawSkin(ctx, .rest, rect: rect, key: key)
        if d > 0 {
            var c = ctx
            c.opacity = Double(d)
            drawSkin(c, .dimmed, rect: rect, key: key)
        }
    }

    private func drawSkin(_ ctx: GraphicsContext, _ skin: Skin, rect: CGRect, key: Int) {
        ctx.fill(Path(roundedRect: rect, cornerRadius: u * 21.9), with: .linearGradient(
            Gradient(colors: [skin.top, skin.bottom]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY + u * 20),
            endPoint: CGPoint(x: rect.midX, y: rect.minY + u * 210)
        ))

        let ridgeW = u * skin.ridgeWidth * rect.width / layout.barWidth
        let ridge = CGRect(
            x: rect.midX - ridgeW / 2,
            y: rect.minY + u * 10.4,
            width: ridgeW,
            height: rect.height - u * 20.8
        )
        ctx.fill(Path(roundedRect: ridge, cornerRadius: ridgeW * 0.345), with: .color(skin.ridge))

        // Pegs through the two cord holes.
        let r = u * 9.07
        for y in [rect.minY + u * 40.2, rect.maxY - u * 40.2] {
            ctx.fill(
                Path(ellipseIn: CGRect(x: rect.midX - r, y: y - r, width: r * 2, height: r * 2)),
                with: .color(skin.pegs)
            )
        }

        // Key number, high on the bar — the near end is below the screen edge.
        ctx.draw(
            Text("\(key + 1)")
                .font(.system(size: max(11, layout.barWidth * 0.36), weight: .bold, design: .default))
                .foregroundStyle(skin.number),
            at: CGPoint(x: rect.midX, y: rect.minY + u * 100)
        )
    }

    /// Sideways offset of a ringing bar, as a fraction of its width.
    private static func ring(age: Double) -> CGFloat {
        guard age >= 0 else { return 0 }
        return CGFloat(0.07 * sin(2 * .pi * 16 * age) * exp(-age / 0.08))
    }
}

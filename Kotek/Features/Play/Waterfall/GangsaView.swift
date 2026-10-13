//
//  GangsaView.swift
//  Kotek
//
//  The instrument, drawn: a carved pelawah frame, bronze bilah on two cords.
//  Every bar the same size — the graduated lengths of a real gangsa were
//  dropped as visual noise; the numbers say low → high well enough. The
//  bottom of the instrument sinks off the screen (see WaterfallPlayView), so
//  it costs less of the stage. The waterfall
//  lands on the top edge of these bars, so both read their geometry from
//  `GangsaLayout` and a lane is exactly one bilah wide.
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

    /// Most of the lane, leaving a narrow strip of the dark well between bars
    /// the way the resonators show on the real thing.
    var barWidth: CGFloat {
        lane * Self.barFill
    }

    private static let barFill: CGFloat = 0.9
    /// Long side over short side of a bar. Gangsa bilah are long and narrow;
    /// a squarer bar reads as a xylophone toy.
    private static let barAspect: CGFloat = 2.5
    static let barInsets: CGFloat = 24 // top + bottom, see GangsaView

    /// The lane that gives a properly proportioned bar in a gangsa this tall.
    static func lane(forHeight height: CGFloat) -> CGFloat {
        (height - barInsets) / barAspect / barFill
    }

    func laneCenter(_ key: Int) -> CGFloat {
        (CGFloat(key) + 0.5) * lane
    }
}

/// Highlights for one bilah this frame, worked out by the caller from the
/// engine, so the instrument itself stays a pure drawing of its inputs.
struct BilahCue: Equatable {
    /// 0…1, how close the next stroke on this bar is.
    var approach: Double = 0
    var strikeNow = false
    var hit = false
    /// 0…1, the left hand should be pinching this bar.
    var damp: Double = 0
    /// A sensor just fired on this bar — the raw hardware, before judging.
    var sensed = false
}

struct GangsaView: View {
    let layout: GangsaLayout
    let voiced: ClosedRange<Int>
    let cues: [Int: BilahCue]
    let tilted: Bool
    /// Wood either side of the lanes.
    let framePad: CGFloat

    // Insets of the bars inside the frame. The bars hang from one straight
    // top line so the waterfall has a single landing edge.
    private let topInset: CGFloat = 10
    private var bottomInset: CGFloat {
        GangsaLayout.barInsets - topInset
    }

    var body: some View {
        GeometryReader { geo in
            let maxLength = geo.size.height - topInset - bottomInset
            ZStack(alignment: .topLeading) {
                frame(size: geo.size)
                Canvas { ctx, _ in
                    drawCords(ctx, maxLength: maxLength)
                    for key in 0 ..< layout.keyCount {
                        drawBar(ctx, key: key, maxLength: maxLength)
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
            .shadow(color: .black.opacity(tilted ? 0.55 : 0.35), radius: tilted ? 18 : 8, y: tilted ? 14 : 4)
        }
    }

    // MARK: - Frame

    private func frame(size: CGSize) -> some View {
        ZStack {
            // Pelawah: carved wood, lacquered red-brown, gold trim.
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(
                    colors: [Color(hex: 0x7A3E26), Color(hex: 0x4E2516)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Theme.gold.opacity(0.75), lineWidth: 1.2)
                .padding(4)
            // The well the bars sit over — the resonators, in shadow.
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: 0x1A120E))
                .padding(.horizontal, framePad - 6)
                .padding(.top, topInset - 4)
                .padding(.bottom, bottomInset - 6)
            // End boards, a little proud of the frame, each with a carved
            // gold diamond — the bit of a gangsa everyone recognises.
            HStack {
                endBoard
                Spacer()
                endBoard
            }
            .padding(.vertical, -5)
        }
        .frame(width: size.width, height: size.height)
    }

    private var endBoard: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(LinearGradient(
                colors: [Color(hex: 0x8C4A2C), Color(hex: 0x5A2C1A)],
                startPoint: .top,
                endPoint: .bottom
            ))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.gold.opacity(0.8), lineWidth: 1.2))
            .overlay(
                Rectangle()
                    .fill(Theme.gold.opacity(0.85))
                    .frame(width: 8, height: 8)
                    .rotationEffect(.degrees(45))
            )
            .frame(width: framePad - 8)
    }

    // MARK: - Bars

    private func barRect(_ key: Int, maxLength: CGFloat) -> CGRect {
        let w = layout.barWidth
        return CGRect(
            x: framePad + layout.laneCenter(key) - w / 2,
            y: topInset,
            width: w,
            height: maxLength
        )
    }

    /// The two cords the bars hang on, straight across under the pegs.
    private func drawCords(_ ctx: GraphicsContext, maxLength: CGFloat) {
        let cord = Color(hex: 0x8E2F22)
        for y in [topInset + pegInset, topInset + maxLength - pegInset] {
            var line = Path()
            line.move(to: CGPoint(x: framePad - 4, y: y))
            line.addLine(to: CGPoint(x: framePad + layout.width + 4, y: y))
            ctx.stroke(line, with: .color(cord), lineWidth: 2)
        }
    }

    private var pegInset: CGFloat {
        12
    }

    private func drawBar(_ ctx: GraphicsContext, key: Int, maxLength: CGFloat) {
        let rect = barRect(key, maxLength: maxLength)
        let shape = Path(roundedRect: rect, cornerRadius: 4)
        let cue = cues[key] ?? BilahCue()
        let isVoiced = voiced.contains(key)

        // Drop shadow onto the well.
        ctx.fill(
            Path(roundedRect: rect.offsetBy(dx: 1.5, dy: 3), cornerRadius: 4),
            with: .color(.black.opacity(0.5))
        )

        // Bronze: lit from the top-left, a soft ridge down the middle.
        ctx.fill(shape, with: .linearGradient(
            Gradient(colors: [Color(hex: 0xEACB92), Color(hex: 0xC9A063), Color(hex: 0x8F6A3A)]),
            startPoint: CGPoint(x: rect.minX, y: rect.minY),
            endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
        ))
        let ridge = CGRect(
            x: rect.midX - rect.width * 0.12,
            y: rect.minY + 3,
            width: rect.width * 0.24,
            height: rect.height - 6
        )
        ctx.fill(
            Path(roundedRect: ridge, cornerRadius: ridge.width / 2),
            with: .color(.white.opacity(0.14))
        )
        ctx.stroke(shape, with: .color(Color(hex: 0x5C4022).opacity(0.9)), lineWidth: 1)

        // Pegs through the two cord holes.
        for y in [rect.minY + pegInset, rect.maxY - pegInset] {
            let peg = CGRect(x: rect.midX - 3, y: y - 3, width: 6, height: 6)
            ctx.fill(Path(ellipseIn: peg), with: .color(Color(hex: 0x2E2018)))
            ctx.fill(Path(ellipseIn: peg.insetBy(dx: 1.8, dy: 1.8)), with: .color(Theme.gold))
        }

        // Key number, engraved just under the top peg — the only part of the
        // bar sure to be on screen with most of the instrument sunk.
        ctx.draw(
            Text("\(key + 1)").font(.sans(11, weight: .bold))
                .foregroundStyle(Color(hex: 0x3D2A16).opacity(0.75)),
            at: CGPoint(x: rect.midX, y: rect.minY + pegInset + 16)
        )

        if !isVoiced {
            ctx.fill(shape, with: .color(Theme.ink.opacity(0.45)))
        }

        // — Cues, quietest first so the strike always wins. —
        if cue.approach > 0 {
            ctx.fill(shape, with: .color(Theme.upcoming.opacity(0.12 + 0.4 * cue.approach)))
        }
        if cue.damp > 0 {
            // Damp: muted red, dashed, with a pinch. Not a target to strike —
            // the outline is broken on purpose so it never reads as one.
            ctx.fill(shape, with: .color(Self.dampColor.opacity(0.55 * cue.damp)))
            ctx.stroke(
                Path(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 3),
                with: .color(Self.dampColor.opacity(cue.damp)),
                style: StrokeStyle(lineWidth: 2.5, dash: [5, 4])
            )
            // Over the key number, high on the bar — the lower half may be
            // below the screen edge.
            let size = CGSize(width: min(18, rect.width * 0.6), height: min(22, rect.width * 0.75))
            DampGlyph.draw(
                in: ctx,
                rect: CGRect(
                    x: rect.midX - size.width / 2,
                    y: rect.minY + pegInset + 16 - size.height / 2,
                    width: size.width,
                    height: size.height
                ),
                color: Theme.cream.opacity(cue.damp)
            )
        }
        if cue.strikeNow {
            ctx.stroke(shape, with: .color(Theme.cream), lineWidth: 3)
        }
        if cue.hit {
            ctx.fill(shape, with: .color(Theme.hit.opacity(0.6)))
        }
        if cue.sensed {
            ctx.stroke(
                Path(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerRadius: 6),
                with: .color(Theme.cream.opacity(0.9)),
                lineWidth: 2
            )
        }
    }

    /// Red leaning grey: "stop this one", without the alarm of the miss red.
    static let dampColor = Color(hex: 0xB0605A)
}

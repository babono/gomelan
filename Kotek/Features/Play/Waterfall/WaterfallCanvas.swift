//
//  WaterfallCanvas.swift
//  Kotek
//
//  The falling notes. Every stroke is a block in its bilah's lane that reaches
//  the bottom edge — the top of the bar — at the instant it is due. Right
//  behind it in the same lane rides a damp cue: the moment the note ends, the
//  left hand pinches that bilah (§5.5).
//
//  One Canvas, reading the engine, so the per-frame redraw stays in here and
//  never reaches the instrument or the chrome.
//

import SwiftUI

struct WaterfallCanvas: View {
    let engine: PlayEngine
    let layout: GangsaLayout
    let voiced: ClosedRange<Int>
    let yourHalf: KotekanHalf

    /// How tall one beat is. Beats, not ms, so the speed of the fall follows
    /// the tempo control and the spacing on screen means the same at 0.5× as
    /// at 1×. Six beats of warning fits the reference shot's density.
    ///
    /// Static so coop's unison bands, drawn across two of these, land on the
    /// same heights as the blocks they join.
    static func pxPerBeat(height: CGFloat) -> CGFloat {
        max(34, height / 6)
    }

    /// A voice's block, from the design drawing: lighter at the top, a
    /// brighter rim. Not `Theme.polosVoice`/`sangsihVoice` — the drawing
    /// deepens both so they sit on the warm ground without glowing.
    private struct Skin {
        var top: Color, bottom: Color, rim: Color
        static let polos = Skin(
            top: Color(hex: 0x678BC6),
            bottom: Color(hex: 0x3E527F),
            rim: Color(hex: 0x7BA2E4)
        )
        static let sangsih = Skin(
            top: Color(hex: 0xA382C6),
            bottom: Color(hex: 0x78529F),
            rim: Color(hex: 0xB391D8)
        )
        static let damp = Skin(
            top: Color(hex: 0x715736),
            bottom: Color(hex: 0x55422D),
            rim: Color(hex: 0x9E7B49)
        )
    }

    private var yourSkin: Skin {
        yourHalf == .polos ? .polos : .sangsih
    }

    private var partnerSkin: Skin {
        yourHalf == .polos ? .sangsih : .polos
    }

    var body: some View {
        // Read here, in body, so Observation ties this view to the clock. The
        // Canvas renderer runs outside body tracking, and without this the
        // waterfall would only move when something else redrew it.
        // swiftlint:disable:next redundant_discardable_let - a bare `_ =` is a () expression in a ViewBuilder
        let _ = engine.currentTimeMs
        Canvas { ctx, size in
            let beatMs = engine.beatLengthMs
            guard beatMs > 0 else { return }
            let pxPerMs = Self.pxPerBeat(height: size.height) / beatMs
            let aheadMs = Double(size.height) / pxPerMs
            let lineY = size.height
            func y(_ msAhead: Double) -> CGFloat {
                lineY - msAhead * pxPerMs
            }

            drawLanes(ctx, size: size)
            drawVerdicts(ctx, lineY: lineY)

            for beat in engine.fallingBeats(aheadMs: aheadMs, behindMs: 0) {
                let yy = y(beat.msAhead)
                var rule = Path()
                rule.move(to: CGPoint(x: 0, y: yy))
                rule.addLine(to: CGPoint(x: size.width, y: yy))
                ctx.stroke(
                    rule,
                    with: .color(Theme.cream.opacity(beat.strong ? 0.16 : 0.06)),
                    lineWidth: beat.strong ? 1 : 0.5
                )
            }

            let notes = engine.fallingNotes(aheadMs: aheadMs, behindMs: beatMs)
            // Partner first, then damp cues, then yours — so the thing you
            // strike is always on top of everything else in its lane.
            for note in notes where note.voice == .partner {
                drawPartner(ctx, note: note, y: y, pxPerMs: pxPerMs)
            }
            for note in notes where note.voice == .yours {
                drawDamp(ctx, note: note, y: y, pxPerMs: pxPerMs)
            }
            for note in notes where note.voice == .yours {
                drawYours(ctx, note: note, y: y, pxPerMs: pxPerMs)
            }

            drawFloaters(ctx, lineY: lineY)
        }
        .clipped()
    }

    // MARK: - Pieces

    /// One warm column over the bars the figure uses, brightening towards
    /// the instrument. No lane lines — the bars below already mark the lanes.
    private func drawLanes(_ ctx: GraphicsContext, size: CGSize) {
        let x = layout.laneCenter(voiced.lowerBound) - layout.lane / 2
        let column = CGRect(x: x, y: 0, width: layout.lane * CGFloat(voiced.count), height: size.height)
        let tint = Color(hex: 0xC39B60)
        ctx.fill(Path(column), with: .linearGradient(
            Gradient(stops: [
                .init(color: tint.opacity(0), location: 0),
                .init(color: tint.opacity(0.13), location: 0.8),
                .init(color: tint.opacity(0.28), location: 1)
            ]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
        ))
    }

    private func block(
        _ note: FallingNote,
        width: CGFloat,
        y: (Double) -> CGFloat,
        pxPerMs: Double,
        minHeight: CGFloat = 20
    ) -> CGRect {
        let bottom = y(note.msAhead)
        let height = max(minHeight, note.durationMs * pxPerMs - 3)
        return CGRect(
            x: layout.laneCenter(note.keyIndex) - width / 2,
            y: bottom - height,
            width: width,
            height: height
        )
    }

    /// Right or wrong, as a glow rising off the rail in the bar's lane:
    /// green for a hit, red for a missed note. It used to recolour the bar
    /// itself, but a miss is judged as the next stroke comes due — the very
    /// moment the damp cue lights that same bar — so the red hid the pinch.
    /// Up here, behind the falling blocks, it covers nothing.
    ///
    /// Gradients as drawn (`correct-hit.svg`, `miss.svg`): their end points
    /// sit beyond the 124 × 89 tile, so the bottom never reaches full colour.
    private func drawVerdicts(_ ctx: GraphicsContext, lineY: CGFloat) {
        let u = layout.unit
        for (key, flash) in engine.keyFlashes {
            let r = CGRect(
                x: layout.laneCenter(key) - u * 62,
                y: lineY - u * 89,
                width: u * 124,
                height: u * 89
            )
            let hit = flash.result.isHit
            let colour = Color(hex: hit ? 0x79EC90 : 0x821C28)
            let fadeTo = hit ? colour.opacity(0) : Color(hex: 0x8F303B, alpha: 0)
            var c = ctx
            c.opacity = 1 - pow(min(1, flash.age / engine.flashDuration), 2)
            c.fill(Path(r), with: .linearGradient(
                Gradient(colors: [colour, fadeTo]),
                startPoint: CGPoint(x: r.midX, y: r.minY + u * (hit ? 223 : 135)),
                endPoint: CGPoint(x: r.midX, y: r.minY + u * (hit ? 11 : 0))
            ))
        }
    }

    private func drawBlock(_ ctx: GraphicsContext, _ r: CGRect, skin: Skin) {
        let shape = Path(roundedRect: r, cornerRadius: min(r.width, r.height) * 0.22)
        ctx.fill(shape, with: .linearGradient(
            Gradient(colors: [skin.top, skin.bottom]),
            startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)
        ))
        ctx.stroke(
            Path(
                roundedRect: r.insetBy(dx: 0.75, dy: 0.75),
                cornerRadius: min(r.width, r.height) * 0.22 - 0.75
            ),
            with: .color(skin.rim),
            lineWidth: 1.5
        )
    }

    /// The other half, drawn as solid as yours: the interlock is the lesson,
    /// and the colour already says whose stroke it is.
    private func drawPartner(
        _ ctx: GraphicsContext,
        note: FallingNote,
        y: (Double) -> CGFloat,
        pxPerMs: Double
    ) {
        drawBlock(ctx, block(note, width: layout.barWidth, y: y, pxPerMs: pxPerMs), skin: partnerSkin)
    }

    /// Keeps its colour after it is judged — the verdict is painted on the
    /// bar it landed on (`GangsaView`), where the eye is at the stroke.
    private func drawYours(
        _ ctx: GraphicsContext,
        note: FallingNote,
        y: (Double) -> CGFloat,
        pxPerMs: Double
    ) {
        drawBlock(ctx, block(note, width: layout.barWidth, y: y, pxPerMs: pxPerMs), skin: yourSkin)
    }

    /// Follows its stroke up the same lane, as long as the stroke, reaching
    /// the bar the instant the note ends: a bronze tile with a pinch, the
    /// colour of the bar it stops, so it never reads as a target.
    private func drawDamp(
        _ ctx: GraphicsContext,
        note: FallingNote,
        y: (Double) -> CGFloat,
        pxPerMs: Double
    ) {
        guard note.dampsAfter else { return }
        let stroke = block(note, width: layout.barWidth, y: y, pxPerMs: pxPerMs)
        let width = layout.barWidth * 0.84
        // Its bottom is the note's end; the 3pt the stroke leaves at its top
        // is the gap between the two.
        let bottom = y(note.msAhead + note.durationMs)
        let r = CGRect(
            x: layout.laneCenter(note.keyIndex) - width / 2,
            y: bottom - stroke.height,
            width: width,
            height: stroke.height
        )
        drawBlock(ctx, r, skin: .damp)
        let iconH = min(r.width * 0.5, r.height - 6)
        let iconW = iconH * 0.8
        DampGlyph.draw(
            in: ctx,
            rect: CGRect(
                x: r.midX - iconW / 2,
                y: r.midY - iconH / 2,
                width: iconW,
                height: iconH
            ),
            color: Color(hex: 0x2B211C)
        )
    }

    /// "PERFECT", "LATE"… rising off the bar that was struck.
    private func drawFloaters(_ ctx: GraphicsContext, lineY: CGFloat) {
        for f in engine.floaters {
            let age = (engine.renderNow - f.bornAt) / engine.floaterDuration
            guard age >= 0, age <= 1 else { continue }
            let colour: Color = switch f.label {
            case .perfect, .goodEarly, .goodLate: Theme.hit
            case .late, .wrongKey: Theme.wrong
            case .miss, .unmatched: Theme.miss
            }
            var c = ctx
            c.opacity = 1 - age
            c.draw(
                Text(f.label.text).font(.sans(12, weight: .black)).foregroundStyle(colour),
                at: CGPoint(x: layout.laneCenter(f.keyIndex), y: lineY - 24 - 26 * age)
            )
        }
    }
}

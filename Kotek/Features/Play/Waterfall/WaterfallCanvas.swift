//
//  WaterfallCanvas.swift
//  Kotek
//
//  The falling notes. Every stroke is a short pill in its bilah's lane that
//  reaches the bottom edge — the gangsa's rail, the one line there is to hit
//  on — at the instant it is due. Above it in the same lane rides a grey
//  damp pill, on a cream stem as long as the note: when the grey reaches the
//  line, the note ends and the left hand pinches that bilah (§5.5).
//
//  The designer's drawing, November 2026. It replaced a stroke block as tall
//  as the note with a dark damp tile of the same height stacked on it, a
//  pinching hand drawn in it (`DampGlyph`): two tall blocks per note, and no
//  telling from them which edge meant "now". The stem says how long the note
//  rings; the pills are the two moments.
//
//  A grey hit line along the foot was tried with them, turning gold under a
//  hit and darker under a pinch. Right above the gangsa's own rail it made
//  two lines, and which one to hit on was less clear than with none.
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
    /// Whether the falling damp tiles show (`DampGuide`).
    var damp: DampGuide = .all

    /// How tall one beat is. Beats, not ms, so the speed of the fall follows
    /// the tempo control and the spacing on screen means the same at 0.5× as
    /// at 1×. Six beats of warning fits the reference shot's density.
    ///
    /// Static so coop's unison bands, drawn across two of these, land on the
    /// same heights as the blocks they join.
    static func pxPerBeat(height: CGFloat) -> CGFloat {
        max(34, height / 6)
    }

    /// A stroke pill's height for a bar this wide — the designer's 222 x 62.
    static func strikeHeight(barWidth: CGFloat) -> CGFloat {
        max(8, barWidth * 0.28)
    }

    /// The damp pill, thinner (222 x 42), and the stem between, narrower.
    private static func dampHeight(barWidth: CGFloat) -> CGFloat {
        max(6, barWidth * 0.19)
    }

    private static let stemFill: CGFloat = 0.61

    private static let dampGrey = Color(hex: 0x9C9FA8)
    private static let stemCream = Color(hex: 0xF5E7D2)

    private var yourColour: Color {
        yourHalf == .polos ? Theme.polosVoice : Theme.sangsihVoice
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

            drawCycles(ctx, size: size, aheadMs: aheadMs, y: y)

            let notes = engine.fallingNotes(aheadMs: aheadMs, behindMs: beatMs)
                .filter { $0.voice == .yours }
            // Only your half falls. The other half used to come down beside
            // it as a muted slate block, and between the two the lanes were
            // twice as busy as the part you actually play; you still hear
            // it. Damp cues first, then the strokes, so the thing you strike
            // is on top in its lane — a short note's damp pill can reach
            // into its own stroke's.
            if damp.showsTiles {
                for note in notes {
                    drawDamp(ctx, note: note, y: y)
                }
            }
            for note in notes {
                drawStroke(ctx, note: note, y: y)
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

    /// A gold rule across the lanes where the next pass begins, "Cycle N"
    /// riding on it. Under the blocks, so the stroke that lands with it
    /// stays on top. The label goes on whichever side the figure leaves
    /// more empty lanes, so it rarely sits under a falling note.
    private func drawCycles(
        _ ctx: GraphicsContext,
        size: CGSize,
        aheadMs: Double,
        y: (Double) -> CGFloat
    ) {
        let leftRoom = layout.laneCenter(voiced.lowerBound) - layout.lane / 2
        let rightRoom = size.width - (layout.laneCenter(voiced.upperBound) + layout.lane / 2)
        let onLeft = leftRoom >= rightRoom
        for cycle in engine.fallingCycles(aheadMs: aheadMs, behindMs: 0) {
            let yy = y(cycle.msAhead)
            var rule = Path()
            rule.move(to: CGPoint(x: 0, y: yy))
            rule.addLine(to: CGPoint(x: size.width, y: yy))
            ctx.stroke(rule, with: .color(Theme.gold.opacity(0.7)), lineWidth: 1.5)
            ctx.draw(
                Text("Cycle \(cycle.number)")
                    .font(.sans(11, weight: .bold))
                    .foregroundStyle(Theme.goldText),
                at: CGPoint(x: onLeft ? 6 : size.width - 6, y: yy - 3),
                anchor: onLeft ? .bottomLeading : .bottomTrailing
            )
        }
    }

    /// A pill in a note's lane, its bottom edge at `bottom`.
    private func pill(_ key: Int, bottom: CGFloat, width: CGFloat, height: CGFloat) -> Path {
        let r = CGRect(x: layout.laneCenter(key) - width / 2, y: bottom - height, width: width, height: height)
        return Path(roundedRect: r, cornerRadius: height * 0.36)
    }

    /// Right or wrong, as a glow rising off the rail in the bar's lane: gold
    /// for a hit, red for a missed note. It used to recolour the bar itself,
    /// but a miss is judged as the next stroke comes due — the very moment
    /// the damp cue lights that same bar — so the red hid the pinch. Up here,
    /// behind the falling notes, it covers nothing.
    ///
    /// A hit was green (`correct-hit.svg`) until the designer's waterfall
    /// made it gold, the colour of a hit everywhere else in the app, and
    /// taller: a column, as if the stroke rang up the lane. The miss is the
    /// drawn one (`miss.svg`), whose gradient's end points sit beyond its
    /// 124 x 89 tile, so the bottom never reaches full colour.
    private func drawVerdicts(_ ctx: GraphicsContext, lineY: CGFloat) {
        let u = layout.unit
        for (key, flash) in engine.keyFlashes {
            let hit = flash.result.isHit
            var c = ctx
            c.opacity = 1 - pow(min(1, flash.age / engine.flashDuration), 2)
            if hit {
                let r = CGRect(
                    x: layout.laneCenter(key) - layout.lane * 0.55,
                    y: lineY - layout.lane * 3,
                    width: layout.lane * 1.1,
                    height: layout.lane * 3
                )
                c.fill(Path(r), with: .linearGradient(
                    Gradient(colors: [Theme.gold.opacity(0), Theme.gold.opacity(0.55)]),
                    startPoint: CGPoint(x: r.midX, y: r.minY),
                    endPoint: CGPoint(x: r.midX, y: r.maxY)
                ))
            } else {
                let r = CGRect(x: layout.laneCenter(key) - u * 62, y: lineY - u * 89, width: u * 124, height: u * 89)
                c.fill(Path(r), with: .linearGradient(
                    Gradient(colors: [Color(hex: 0x821C28), Color(hex: 0x8F303B, alpha: 0)]),
                    startPoint: CGPoint(x: r.midX, y: r.minY + u * 135),
                    endPoint: CGPoint(x: r.midX, y: r.minY)
                ))
            }
        }
    }

    /// The stroke: a short pill in your voice's colour, its bottom edge on
    /// the rail at the instant it is due. Keeps its colour after it is
    /// judged — the verdict glows in the lane.
    private func drawStroke(_ ctx: GraphicsContext, note: FallingNote, y: (Double) -> CGFloat) {
        let h = Self.strikeHeight(barWidth: layout.barWidth)
        ctx.fill(
            pill(note.keyIndex, bottom: y(note.msAhead), width: layout.barWidth, height: h),
            with: .color(yourColour)
        )
    }

    /// Follows its stroke up the same lane: a cream stem from the stroke to a
    /// grey pill whose bottom edge reaches the rail the instant the note
    /// ends. Grey, not a voice's colour, so it never reads as a target.
    private func drawDamp(_ ctx: GraphicsContext, note: FallingNote, y: (Double) -> CGFloat) {
        guard note.dampsAfter else { return }
        let w = layout.barWidth
        let strokeTop = y(note.msAhead) - Self.strikeHeight(barWidth: w)
        let dampBottom = y(note.msAhead + note.durationMs)
        if strokeTop > dampBottom {
            let stemW = w * Self.stemFill
            let stem = CGRect(
                x: layout.laneCenter(note.keyIndex) - stemW / 2,
                y: dampBottom - 1,
                width: stemW,
                height: strokeTop - dampBottom + 2
            )
            ctx.fill(Path(stem), with: .color(Self.stemCream))
        }
        let h = Self.dampHeight(barWidth: w)
        ctx.fill(pill(note.keyIndex, bottom: dampBottom, width: w, height: h), with: .color(Self.dampGrey))
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

//
//  WaterfallCanvas.swift
//  Kotek
//
//  The falling notes. Every stroke is a block in its bilah's lane that reaches
//  the bottom edge — the top of the bar — at the instant it is due. Beside it,
//  in the lane of the bar struck before, rides a damp cue: the left hand pinches
//  the previous bilah as the right strikes the next (§5.5).
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
    private func pxPerBeat(height: CGFloat) -> CGFloat {
        max(34, height / 6)
    }

    private var yourColor: Color { yourHalf == .polos ? Theme.polosVoice : Theme.sangsihVoice }
    private var partnerColor: Color { yourHalf == .polos ? Theme.sangsihVoice : Theme.polosVoice }

    var body: some View {
        // Read here, in body, so Observation ties this view to the clock. The
        // Canvas renderer runs outside body tracking, and without this the
        // waterfall would only move when something else redrew it.
        let _ = engine.currentTimeMs
        Canvas { ctx, size in
            let beatMs = engine.beatLengthMs
            guard beatMs > 0 else { return }
            let pxPerMs = pxPerBeat(height: size.height) / beatMs
            let aheadMs = Double(size.height) / pxPerMs
            let lineY = size.height
            func y(_ msAhead: Double) -> CGFloat { lineY - msAhead * pxPerMs }

            drawLanes(ctx, size: size)

            for beat in engine.fallingBeats(aheadMs: aheadMs, behindMs: 0) {
                let yy = y(beat.msAhead)
                var rule = Path()
                rule.move(to: CGPoint(x: 0, y: yy))
                rule.addLine(to: CGPoint(x: size.width, y: yy))
                ctx.stroke(rule, with: .color(Theme.cream.opacity(beat.strong ? 0.16 : 0.06)),
                           lineWidth: beat.strong ? 1 : 0.5)
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

            drawHitLine(ctx, size: size)
            drawFloaters(ctx, lineY: lineY)
        }
        .clipped()
    }

    // MARK: - Pieces

    private func drawLanes(_ ctx: GraphicsContext, size: CGSize) {
        for key in 0 ..< layout.keyCount {
            let x = layout.laneCenter(key) - layout.lane / 2
            if voiced.contains(key) {
                ctx.fill(Path(CGRect(x: x, y: 0, width: layout.lane, height: size.height)),
                         with: .linearGradient(
                             Gradient(colors: [.clear, Theme.cream.opacity(0.05)]),
                             startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
            if key > 0 {
                var edge = Path()
                edge.move(to: CGPoint(x: x, y: 0))
                edge.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(edge, with: .color(Theme.cream.opacity(0.06)), lineWidth: 0.5)
            }
        }
    }

    private func block(_ note: FallingNote, width: CGFloat, y: (Double) -> CGFloat,
                       pxPerMs: Double, minHeight: CGFloat = 20) -> CGRect {
        let bottom = y(note.msAhead)
        let height = max(minHeight, note.durationMs * pxPerMs - 3)
        return CGRect(x: layout.laneCenter(note.keyIndex) - width / 2, y: bottom - height,
                      width: width, height: height)
    }

    /// The other half: a ghost, so the interlock is visible without competing
    /// with what is yours to play.
    private func drawPartner(_ ctx: GraphicsContext, note: FallingNote,
                             y: (Double) -> CGFloat, pxPerMs: Double) {
        let r = block(note, width: layout.barWidth * 0.62, y: y, pxPerMs: pxPerMs)
        let shape = Path(roundedRect: r, cornerRadius: 5)
        ctx.fill(shape, with: .color(partnerColor.opacity(0.14)))
        ctx.stroke(shape, with: .color(partnerColor.opacity(0.4)), lineWidth: 1)
    }

    private func drawYours(_ ctx: GraphicsContext, note: FallingNote,
                           y: (Double) -> CGFloat, pxPerMs: Double) {
        let r = block(note, width: layout.barWidth, y: y, pxPerMs: pxPerMs)
        let shape = Path(roundedRect: r, cornerRadius: 6)
        let base: Color = switch note.outcome {
        case .some(.miss), .some(.wrongKey): Theme.stone
        case .some: Theme.hit
        case .none: yourColor
        }
        let faded = note.outcome == .miss || note.outcome == .wrongKey
        ctx.fill(shape, with: .linearGradient(
            Gradient(colors: [base.opacity(faded ? 0.35 : 0.75), base.opacity(faded ? 0.5 : 1)]),
            startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
        ctx.stroke(shape, with: .color(.white.opacity(0.35)), lineWidth: 1)
        ctx.draw(Text("\(note.keyIndex + 1)").font(.sans(13, weight: .black))
                    .foregroundStyle(Theme.ink.opacity(faded ? 0.5 : 0.9)),
                 at: CGPoint(x: r.midX, y: r.maxY - 11))
    }

    /// Rides beside its stroke, same height, in the lane of the bar to damp.
    /// Narrower, dashed and hatched with a pinch — it is never a target.
    private func drawDamp(_ ctx: GraphicsContext, note: FallingNote,
                          y: (Double) -> CGFloat, pxPerMs: Double) {
        guard let dampKey = note.dampKey else { return }
        let width = layout.barWidth * 0.66
        let bottom = y(note.msAhead)
        let height = max(18, min(30, note.durationMs * pxPerMs - 3))
        let r = CGRect(x: layout.laneCenter(dampKey) - width / 2, y: bottom - height,
                       width: width, height: height)
        let shape = Path(roundedRect: r, cornerRadius: 5)
        let colour = GangsaView.dampColor

        // A faint tie to the stroke it belongs to, so a pair reads as a pair
        // even when the damp lane is not the neighbour.
        let target = layout.laneCenter(note.keyIndex)
        let fromX = target > r.midX ? r.maxX : r.minX
        let toX = target > r.midX ? target - layout.barWidth / 2 : target + layout.barWidth / 2
        var tie = Path()
        tie.move(to: CGPoint(x: fromX, y: r.midY))
        tie.addLine(to: CGPoint(x: toX, y: r.midY))
        ctx.stroke(tie, with: .color(colour.opacity(0.5)),
                   style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

        ctx.fill(shape, with: .color(colour.opacity(0.28)))
        ctx.stroke(shape, with: .color(colour.opacity(0.9)),
                   style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        var pinch = ctx.resolve(Image(systemName: "hand.pinch.fill"))
        pinch.shading = .color(Theme.cream.opacity(0.85))
        let icon = min(14, r.height - 6)
        ctx.draw(pinch, in: CGRect(x: r.midX - icon / 2, y: r.midY - icon / 2, width: icon, height: icon))
    }

    private func drawHitLine(_ ctx: GraphicsContext, size: CGSize) {
        let band = CGRect(x: 0, y: size.height - 10, width: size.width, height: 10)
        ctx.fill(Path(band), with: .linearGradient(
            Gradient(colors: [.clear, Theme.gold.opacity(0.35)]),
            startPoint: CGPoint(x: 0, y: band.minY), endPoint: CGPoint(x: 0, y: band.maxY)))
        var line = Path()
        line.move(to: CGPoint(x: 0, y: size.height - 1))
        line.addLine(to: CGPoint(x: size.width, y: size.height - 1))
        ctx.stroke(line, with: .color(Theme.gold.opacity(0.9)), lineWidth: 2)
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
            c.draw(Text(f.label.text).font(.sans(12, weight: .black)).foregroundStyle(colour),
                   at: CGPoint(x: layout.laneCenter(f.keyIndex), y: lineY - 24 - 26 * age))
        }
    }
}

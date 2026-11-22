//
//  WaterfallCanvas.swift
//  Kotek
//
//  The falling notes. Every stroke is a short pill in its bilah's lane that
//  reaches the bottom edge — the gangsa's rail, the one line there is to hit
//  on — at the instant it is due. Above it in the same lane rides a cream
//  stem as long as the note, capped with a short beige damp block: when the
//  cap reaches the line, the note ends and the left hand pinches that bilah
//  (§5.5).
//
//  The designer's drawing, November 2026. It replaced a stroke block as tall
//  as the note with a dark damp tile of the same height stacked on it, a
//  pinching hand drawn in it (`DampGlyph`): two tall blocks per note, and no
//  telling from them which edge meant "now". The stem says how long the note
//  rings; the pills are the two moments.
//
//  The damp was first a grey pill as wide as the stroke, the stem running
//  between them. It drew the eye as much as the stroke did; the designer's
//  second pass made it the stem's own cap, its width and in its outline's
//  beige, smaller than the stroke and quieter than it.
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
    /// No sensors: every stroke lands as a hit, as the gangsa rings for it
    /// (`GangsaStage.autoStrikes`), so the line flares for it too.
    var autoStrikes = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long a damp's press plays out on the line and on its bilah.
    static let dampEffectMs = 600.0

    /// How tall one beat is. Beats, not ms, so the speed of the fall follows
    /// the tempo control and the spacing on screen means the same at 0.5× as
    /// at 1×. Six beats of warning fits the reference shot's density.
    ///
    /// Static so coop's unison bands, drawn across two of these, land on the
    /// same heights as the blocks they join.
    static func pxPerBeat(height: CGFloat) -> CGFloat {
        max(34, height / 6)
    }

    /// A stroke pill's height for a bar this wide. The designer's 222 x 62
    /// (0.28) at first; taller since the pill carries its bilah's number,
    /// which was too small to read at that height (0.34 still was).
    static func strikeHeight(barWidth: CGFloat) -> CGFloat {
        max(8, barWidth * 0.42)
    }

    /// The damp cap, about two fifths of the stroke's height (26 to its 66 in
    /// the designer's drawing), on a stem 132 of the stroke's 187 wide.
    private static func dampHeight(barWidth: CGFloat) -> CGFloat {
        max(4, strikeHeight(barWidth: barWidth) * 0.4)
    }

    private static let stemFill: CGFloat = 0.7

    // The cap and the stem's outline, one colour, so they read as one piece
    // (`Theme.dampBeige`, `Theme.stemCream`, shared with Studio's roll).

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
            let lineY = size.height - GangsaLayout.lineInset
            func y(_ msAhead: Double) -> CGFloat {
                lineY - msAhead * pxPerMs
            }

            drawLanes(ctx, lineY: lineY)
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

            // Far enough back for a damp to play out on the line after a long note.
            let notes = engine.fallingNotes(aheadMs: aheadMs, behindMs: max(beatMs * 4, 1000))
                .filter { $0.voice == .yours }
            // Only your half falls. The other half used to come down beside
            // it as a muted slate block, and between the two the lanes were
            // twice as busy as the part you actually play; you still hear
            // it. Damp cues first, then the strokes, so the thing you strike
            // is on top in its lane — a short note's damp pill can reach
            // into its own stroke's.
            // Above the line only: a note that has landed is gone into it.
            var falling = ctx
            falling.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: lineY)))
            if damp.showsTiles {
                for note in notes {
                    drawDamp(falling, note: note, y: y)
                }
            }
            for note in notes {
                drawStroke(falling, note: note, y: y)
            }

            drawRail(ctx, lineY: lineY)
            // A bar shows the later of its hit and its damp, never both: a
            // damp hides the pad of the hit before it, still fading, which
            // stacked on the grey one; a hit as the bar is damped — a repeated
            // note — is the new stroke, and hides the damp.
            let hits = hits(notes)
            var pinched: Set<Int> = []
            if damp.showsHand {
                for note in GangsaStage.pinches(notes) {
                    guard let held = pinchHeld(note) else { continue }
                    if let hit = hits[note.keyIndex], hit <= held / 1000 + 0.01 { continue }
                    drawPinch(ctx, note: note, held: held, lineY: lineY)
                    pinched.insert(note.keyIndex)
                }
            }
            for (key, age) in hits where !pinched.contains(key) {
                drawHit(ctx, key: key, age: age, lineY: lineY)
            }

            drawFloaters(ctx, lineY: lineY)
        }
        .clipped()
    }

    // MARK: - Pieces

    /// A faint line between every lane, the whole width, and one warm column
    /// over the bars the figure uses, brightening towards the instrument —
    /// the part of the gangsa the notes can land on. The lines came with the
    /// tiles (November 2026); over bronze bars the bars marked the lanes.
    /// Both stop at the hit line: run on to the edge, they showed under it.
    private func drawLanes(_ ctx: GraphicsContext, lineY: CGFloat) {
        for edge in 0 ... layout.keyCount {
            let x = CGFloat(edge) * layout.lane
            ctx.fill(
                Path(CGRect(x: x - 0.5, y: 0, width: 1, height: lineY)),
                with: .color(Color(hex: 0xEEE3CD))
            )
        }
        let x = layout.laneCenter(voiced.lowerBound) - layout.lane / 2
        let column = CGRect(x: x, y: 0, width: layout.lane * CGFloat(voiced.count), height: lineY)
        let tint = Color(hex: 0xC39B60)
        ctx.fill(Path(column), with: .linearGradient(
            Gradient(stops: [
                .init(color: tint.opacity(0), location: 0),
                .init(color: tint.opacity(0.13), location: 0.8),
                .init(color: tint.opacity(0.28), location: 1)
            ]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: lineY)
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

    /// A missed note, as a red glow rising off the line in the bar's lane
    /// (`miss.svg`, whose gradient's end points sit beyond its 124 x 89 tile,
    /// so the bottom never reaches full colour). It used to recolour the bar
    /// itself, but a miss is judged as the next stroke comes due — the very
    /// moment the damp cue lights that same bar — so the red hid the pinch.
    ///
    /// A hit glowed here too: green, then a gold column up the lane. It is
    /// the line's flare now (`drawHit`) — the glow said "hit" after the fact,
    /// and read as where to look next.
    private func drawVerdicts(_ ctx: GraphicsContext, lineY: CGFloat) {
        let u = layout.unit
        for (key, flash) in engine.keyFlashes where !flash.result.isHit {
            var c = ctx
            c.opacity = 1 - pow(min(1, flash.age / engine.flashDuration), 2)
            let r = CGRect(x: layout.laneCenter(key) - u * 62, y: lineY - u * 89, width: u * 124, height: u * 89)
            c.fill(Path(r), with: .linearGradient(
                Gradient(colors: [Color(hex: 0x821C28), Color(hex: 0x8F303B, alpha: 0)]),
                startPoint: CGPoint(x: r.midX, y: r.minY + u * 135),
                endPoint: CGPoint(x: r.midX, y: r.minY)
            ))
        }
    }

    /// The stroke: a short pill in your voice's colour, its bottom edge on
    /// the line at the instant it is due, carrying its bilah's number. Keeps
    /// its colour after it is judged — the verdict is on the line.
    private func drawStroke(_ ctx: GraphicsContext, note: FallingNote, y: (Double) -> CGFloat) {
        let h = Self.strikeHeight(barWidth: layout.barWidth)
        let bottom = y(note.msAhead)
        ctx.fill(
            pill(note.keyIndex, bottom: bottom, width: layout.barWidth, height: h),
            with: .color(yourColour)
        )
        guard h >= 10 else { return }
        ctx.draw(
            Text("\(note.keyIndex + 1)")
                .font(.system(size: h * 0.8, weight: .semibold, design: .rounded))
                .foregroundStyle(yourColour.mix(with: .white, by: 0.45)),
            at: CGPoint(x: layout.laneCenter(note.keyIndex), y: bottom - h / 2)
        )
    }

    /// Follows its stroke up the same lane: a cream stem, outlined in beige,
    /// from the stroke to its beige cap, whose bottom edge reaches the rail
    /// the instant the note ends. Beige, not a voice's colour, so it never
    /// reads as a target.
    private func drawDamp(_ ctx: GraphicsContext, note: FallingNote, y: (Double) -> CGFloat) {
        guard note.dampsAfter else { return }
        let w = layout.barWidth
        let stemW = w * Self.stemFill
        let x = layout.laneCenter(note.keyIndex) - stemW / 2
        let strokeTop = y(note.msAhead) - Self.strikeHeight(barWidth: w)
        let dampBottom = y(note.msAhead + note.durationMs)
        let capTop = dampBottom - Self.dampHeight(barWidth: w)
        // Into the stroke a little, so the stem meets it without a seam. A
        // note too short for a stem is the cap alone, under its stroke.
        let foot = max(strokeTop + 2, dampBottom)
        let r = stemW * 0.1
        let outline = UnevenRoundedRectangle(topLeadingRadius: r, topTrailingRadius: r)
            .path(in: CGRect(x: x, y: capTop, width: stemW, height: foot - capTop))
        ctx.fill(outline, with: .color(Theme.dampBeige))
        if foot > dampBottom {
            let edge = max(1, w * 0.02)
            let stem = CGRect(x: x + edge, y: dampBottom, width: stemW - 2 * edge, height: foot - dampBottom)
            ctx.fill(Path(stem), with: .color(Theme.stemCream))
        }
    }

    // MARK: - The line

    // The designer's play screen, November 2026, as worked out in the mockup
    // (sizes there are on a 45 pt bilah, hence `layout.barWidth / 45`).
    private static let rail = Color(hex: 0xEDC97A)
    private static let goldPad = Color(hex: 0xF0B848)
    private static let dampPad = Color(hex: 0xBDC1CB)
    private static let dampLine = Color(hex: 0x8F93A0)

    /// The one line to hit on, across the lanes: 3 pt of pale gold on a faint
    /// warm shadow, so it holds against the cream. Not full Kuning — that is
    /// the hit's pad, and a line in it hid the pad. A thin grey hit line was
    /// tried once above the gangsa's own rail and made two lines; there is
    /// no rail now (`GangsaView`).
    private func drawRail(_ ctx: GraphicsContext, lineY: CGFloat) {
        let w = layout.width
        ctx.fill(
            Path(CGRect(x: 0, y: lineY + 1.5, width: w, height: 1.5)),
            with: .color(Color(hex: 0xA9781E, alpha: 0.18))
        )
        ctx.fill(
            Path(roundedRect: CGRect(x: 0, y: lineY - 1.5, width: w, height: 3), cornerRadius: 1.5),
            with: .color(Self.rail)
        )
    }

    /// Each bar's hit and how long ago: judged hits from the engine, or with
    /// no sensors every stroke that has landed.
    private func hits(_ notes: [FallingNote]) -> [Int: Double] {
        var hits = engine.keyFlashes.filter(\.value.result.isHit).mapValues(\.age)
        if autoStrikes {
            for note in notes where note.msAhead <= 0 && -note.msAhead < engine.flashDuration * 1000 {
                hits[note.keyIndex] = min(hits[note.keyIndex] ?? .infinity, -note.msAhead / 1000)
            }
        }
        return hits
    }

    /// A hit lands on the line as a gold pad that rings: white-hot for the
    /// first 80 ms, its top edge rippling with the bilah's ring and settling
    /// as it fades, a gold halo blooming up and out of it, a few sparks
    /// thrown off — a sharp attack and a slow tail, over the engine's flash.
    /// (A white flare along the line itself was tried first; the designer
    /// kept the pad and wanted it to glow. It popped up and settled at
    /// first, and the ripple was the damp's; the designer swapped them — a
    /// struck bilah is the one that rings.)
    private func drawHit(_ ctx: GraphicsContext, key: Int, age: Double, lineY: CGFloat) {
        let s = layout.barWidth / 45
        let x = layout.laneCenter(key)
        let t = min(1, age / engine.flashDuration)
        let fade = pow(1 - t, 2)
        let bloom = reduceMotion ? 1 : 1 - pow(1 - t, 3)
        let flash = max(0, 1 - age / 0.08)

        // The halo: an ellipse half-sunk into the line, so it fans upward.
        var glow = ctx
        glow.translateBy(x: x, y: lineY)
        glow.scaleBy(x: 1, y: 0.6)
        let r = (46 + 34 * bloom) * s
        glow.clip(to: Path(CGRect(x: -r, y: -r, width: r * 2, height: r)))
        glow.opacity = fade
        glow.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .radialGradient(
            Gradient(stops: [
                .init(color: Color(hex: 0xFFE296, alpha: 0.9), location: 0),
                .init(color: Theme.gold.opacity(0.5), location: 0.3),
                .init(color: Theme.gold.opacity(0), location: 1)
            ]),
            center: .zero, startRadius: 0, endRadius: r
        ))
        if flash > 0 {
            let c = 34 * s
            glow.opacity = flash
            glow.fill(Path(ellipseIn: CGRect(x: -c, y: -c, width: c * 2, height: c * 2)), with: .radialGradient(
                Gradient(colors: [Color(hex: 0xFFFCF0), Color(hex: 0xFFF0C8, alpha: 0)]),
                center: .zero, startRadius: 0, endRadius: c
            ))
        }

        // Sparks: a few motes thrown up off the pad, slowing and fading. The
        // same spread on a bar every time — hashed from the key, not random,
        // so a frame is a pure function of the clock.
        if !reduceMotion {
            var sparks = ctx
            for i in 0 ..< 6 {
                let h = sin(Double(key + 1) * 12.9898 + Double(i) * 78.233) * 43758.5453
                let rnd = h - h.rounded(.down)
                let dx = (Double(i) - 2.5) * 7 + (rnd - 0.5) * 6
                let rise = 22 + rnd * 26
                let p = CGPoint(x: x + dx * (0.4 + bloom) * s, y: lineY - (3 + rise * bloom) * s)
                let d = (1.2 + rnd) * s
                sparks.opacity = fade * (0.6 + 0.4 * rnd)
                sparks.fill(
                    Path(ellipseIn: CGRect(x: p.x - d, y: p.y - d, width: d * 2, height: d * 2)),
                    with: .color(Color(hex: 0xF2A623))
                )
            }
        }

        // The pad: ringing, and glowing.
        var pad = ctx
        pad.translateBy(x: x, y: lineY - 0.5 * s)
        pad.addFilter(.shadow(color: Color(hex: 0xFFC85A, alpha: fade), radius: 9 * s))
        pad.addFilter(.shadow(color: Color(hex: 0xFFF0C8, alpha: fade), radius: 3 * s))
        let shape = ringingPad(amp: reduceMotion ? 0 : 7 * exp(-t * 2.5), phase: age * 44, scale: s)
        let colour = flash > 0 ? Color(hex: 0xFFD27A) : Self.goldPad
        pad.fill(shape, with: .color(colour))
        pad.stroke(shape, with: .color(colour), style: StrokeStyle(lineWidth: 4 * s, lineJoin: .round))
    }

    /// The left hand's moment on the line, the hit run backwards: where a hit
    /// throws light out and rings, a damp swallows the light and stops the
    /// ring. The grey pad lands still rippling as the hit's did and is
    /// pressed flat at once — squashed, held down — while a slate halo pulls
    /// in to it. The pad holds as long as the pinch does (`GangsaStage`).
    /// (The ripple dying slowly here, and a pop on the hit, was the first
    /// way round; the designer swapped them.)
    /// `held` ms into the pinch (`pinchHeld`).
    private func drawPinch(_ ctx: GraphicsContext, note: FallingNote, held: Double, lineY: CGFloat) {
        let hold = GangsaStage.pinchHold(note)
        let s = layout.barWidth / 45
        let x = layout.laneCenter(note.keyIndex)
        let age = held / 1000
        let t = min(1, held / Self.dampEffectMs)
        let fade = 1 - t

        // The halo, collapsing inward: wide and faint at first, gone to a point.
        var halo = ctx
        let r = (70 - 52 * (1 - pow(1 - t, 3))) * s
        halo.translateBy(x: x, y: lineY)
        halo.scaleBy(x: 1, y: 0.55)
        halo.clip(to: Path(CGRect(x: -r, y: -r, width: r * 2, height: r)))
        halo.opacity = 0.55 * fade
        halo.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .radialGradient(
            Gradient(stops: [
                .init(color: Color(hex: 0x6E7486, alpha: 0.75), location: 0),
                .init(color: Self.dampLine.opacity(0.35), location: 0.5),
                .init(color: Self.dampLine.opacity(0), location: 1)
            ]),
            center: .zero, startRadius: 0, endRadius: r
        ))

        // The pad: still ringing as it lands, then pressed flat inside 120 ms
        // — the stop is the point, so it is quick — squashed wide under the
        // press, and held down.
        let stop = min(1, age / 0.12)
        let press = min(1, age / 0.08)
        let squash = reduceMotion || age >= 0.2 ? 0 : sin(age / 0.2 * .pi)
        let amp = reduceMotion ? 0 : 6 * pow(1 - stop, 2)
        var pad = ctx
        pad.opacity = held < hold ? 1 : fade
        pad.translateBy(x: x, y: lineY + (press - 0.5) * s)
        pad.scaleBy(x: 1 + 0.15 * squash, y: 1 - 0.4 * squash)
        let shape = ringingPad(amp: amp, phase: age * 44, scale: s)
        let colour = t < 0.5 ? Self.dampLine : Self.dampPad
        pad.fill(shape, with: .color(colour))
        pad.stroke(shape, with: .color(colour), style: StrokeStyle(lineWidth: 4 * s, lineJoin: .round))
    }

    /// How many ms into its pinch a note is, while the pinch plays out on the
    /// line: the hold (`GangsaStage`'s, 90…400 ms) or the effect, if longer.
    private func pinchHeld(_ note: FallingNote) -> Double? {
        let held = -(note.msAhead + note.durationMs)
        let hold = GangsaStage.pinchHold(note)
        return held >= 0 && held < max(hold, Self.dampEffectMs) ? held : nil
    }

    /// A pad on the line, centred on the origin, whose top edge waves `amp`
    /// (mockup points) — pinned at both ends, like a bilah on its cord. Drawn
    /// 2 pt inside the pad's 54 x 5 outline, for the caller to fill and
    /// stroke 4 pt wide with round joins: the plain pad's size, every corner
    /// and crest rounded. Flat at `amp` 0.
    private func ringingPad(amp: Double, phase: Double, scale s: CGFloat) -> Path {
        var wave = Path()
        wave.move(to: CGPoint(x: -25 * s, y: 0.5 * s))
        for i in 0 ... 48 {
            let u = Double(i) / 48
            let crest = -0.5 - amp * sin(u * .pi) * sin(u * .pi * 4 - phase)
            wave.addLine(to: CGPoint(x: (-25 + 50 * u) * s, y: crest * s))
        }
        wave.addLine(to: CGPoint(x: 25 * s, y: 0.5 * s))
        wave.closeSubpath()
        return wave
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

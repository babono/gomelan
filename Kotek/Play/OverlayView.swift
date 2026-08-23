//
//  OverlayView.swift
//  Kotek
//
//  The guidance layer drawn over the live camera feed (PRD §5.2, §13.5). This is
//  the PRIMARY cue: you are looking at the instrument, not at a score, so the
//  bilah itself has to say when to strike. Peripheral legibility is the
//  constraint — large shapes, high contrast, no text during play. The scrolling
//  score is a separate, secondary layer — see NotesRiver.
//
//  Drawn in a single Canvas. It used to be a ZStack of five shapes per key, each
//  with its own shadow, rebuilt sixty times a second: SwiftUI had to diff ~50
//  views a frame and the GPU an offscreen pass per shadow. One canvas is one
//  draw pass, and the bilah numbers arrive as pre-rendered symbols so no text is
//  resolved per frame.
//
//  It reads `engine.renderStates` itself rather than taking them as a parameter,
//  so per-frame invalidation stops here instead of re-evaluating the whole play
//  screen — top bar, buttons and all — on every tick.
//

import SwiftUI

struct OverlayView: View {
    let keys: [InstrumentKey]
    let engine: PlayEngine

    var body: some View {
        //R Read in the body, NOT inside the draw closure: Observation registers
        //R the dependency while the body runs, so a read that only happens at
        //R draw time would never invalidate the view and the cue would freeze.
        let states = engine.renderStates

        return Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
            for key in keys {
                draw(key, state: states[key.index] ?? KeyRenderState(), in: &ctx, size: size)
            }
        } symbols: {
            ForEach(keys) { key in
                Text(bilahLabel(key.index, count: keys.count))
                    .font(.serif(15, weight: .bold))
                    .foregroundStyle(Theme.copper.opacity(0.85))
                    .tag(key.index)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ key: InstrumentKey, state: KeyRenderState,
                      in ctx: inout GraphicsContext, size: CGSize) {
        let rect = key.rect.rect(in: size)
        let radius = Theme.keyCornerRadius
        let shape = Path(roundedRect: rect, cornerRadius: radius)

        // 1. The bilah always reads as a target, struck or not.
        ctx.fill(shape, with: .color(.black.opacity(0.18)))
        ctx.stroke(shape, with: .color(Theme.copper.opacity(0.4)), lineWidth: 1.5)

        if let symbol = ctx.resolveSymbol(id: key.index) {
            ctx.draw(symbol, at: CGPoint(x: rect.midX, y: rect.maxY - 12))
        }

        // 2. The countdown to this stroke, filling from the bottom (§13.5). The
        //    key is the guidance now, so the approach has to be readable on the
        //    bilah alone, without looking down at the score.
        if state.fill > 0, !state.strikeNow {
            let fill = min(1, max(0, state.fill))
            var layer = ctx
            layer.clip(to: shape)
            let filled = CGRect(x: rect.minX,
                                y: rect.maxY - rect.height * fill,
                                width: rect.width,
                                height: rect.height * fill)
            layer.fill(Path(filled), with: .color(Theme.copper.opacity(0.22 + 0.18 * fill)))
        }

        // 2b. Rings closing in from all four sides, so the approach also reads
        //     in the corner of the eye, where a fill level does not. One per
        //     upcoming stroke on this bilah, nested — a bar you are about to
        //     strike twice says so, which is the shape of a kotekan.
        //
        //     Drawn OUTSIDE the fill's `!strikeNow` guard on purpose: while you
        //     are playing a note the ring for the next strike on that same bar
        //     is the most useful thing on the screen, and hiding it was why a
        //     7 → 7 repeat gave no warning at all.
        for progress in state.approaches {
            let fill = min(1, max(0, progress))
            let pad = (1 - fill) * 20
            let ring = Path(roundedRect: rect.insetBy(dx: -pad, dy: -pad),
                            cornerRadius: radius + pad * 0.5)
            // Squared, so it comes in almost invisible and only gathers weight
            // in the last stretch. At a linear ramp — or worse, a constant one —
            // a bilah a second away shouts as loudly as the one landing, which
            // is how a lookahead turns into noise. Line weight follows, so the
            // near ring is heavier as well as brighter.
            let presence = fill * fill
            ctx.stroke(ring,
                       with: .color(Theme.copper.opacity(0.10 + 0.90 * presence)),
                       lineWidth: 1 + 1.4 * fill)
        }

        // 3. NOW. A cream border plus a wash inside it — bright enough to catch
        //    peripherally, and cheaper than a shadow.
        if state.strikeNow {
            ctx.fill(shape, with: .color(Theme.cream.opacity(0.16)))
            ctx.stroke(shape, with: .color(Theme.cream), lineWidth: 3)
        }

        // 4. Your strike landing: the only solid fill on the instrument, and
        //    the only colour it ever takes.
        if state.hit {
            ctx.fill(shape, with: .color(Theme.hit.opacity(0.85)))
        }

        // 5. Damp hint on the key you should be silencing (§5.5).
        if state.damp {
            ctx.stroke(shape, with: .color(Theme.copper),
                       style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
        }
    }

}

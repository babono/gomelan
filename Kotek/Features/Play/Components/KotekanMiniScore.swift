//
//  KotekanMiniScore.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// One kotekan's shape, small enough to live inside a picker card.
/// Drawn straight from the figure rather than from a `PlayEngine`, which is the
/// whole point: only one card is ever playing, but EVERY card can show what its
/// figure looks like. A shape you can compare at a glance says more about a
/// kotekan than a sentence of prose about it does.
struct KotekanMiniScore: View {
    let kotekan: Kotekan
    /// The engine, when this figure is the one sounding — nil on every other card.
    var engine: PlayEngine?

    var body: some View {
        ZStack {
            blocks
            if let engine { Playhead(engine: engine) }
        }
    }

    /// The figure itself.
    private var blocks: some View {
        let page = engine?.scorePage ?? 0

        return Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
            let range = kotekan.voicedKeyRange
            let rows = CGFloat(max(1, range.count))
            let lane = size.height / rows
            let total = max(1, kotekan.slotsPerCycle)
            let pageSlots = min(total, PlayEngine.colotomicBeats)
            let firstSlot = min(page * pageSlots, max(0, total - pageSlots))
            let slotW = size.width / CGFloat(pageSlots)
            let blockW = max(3, slotW * 0.82)
            // A tile, never a bar: filling the lane made every block as tall as
            // the card allowed, and on a taller card the score read as a row of
            // needles. Extra height is air between the rows instead. The 7pt
            // floor is for the dense figures, whose narrow slots made the tiles dots.
            let blockH = max(3, min(lane - 2, max(7, blockW * 0.65)))

            func y(_ key: Int) -> CGFloat {
                size.height - CGFloat(key - range.lowerBound + 1) * lane + (lane - blockH) / 2
            }

            // Same skin as the waterfall's blocks, with a rim scaled down to
            // the card: the waterfall's 1.5pt eats most of a 6pt block.
            let rimWidth = min(1, blockH * 0.12)

            func draw(_ key: Int, slot: Int, skin: VoiceSkin, half: Bool, rightHalf: Bool) {
                let rect = CGRect(
                    x: CGFloat(slot) * slotW,
                    y: y(key),
                    width: blockW,
                    height: blockH
                )
                guard half else { skin.draw(ctx, rect, rimWidth: rimWidth)
                    return
                }
                var layer = ctx
                layer.clip(to: Path(CGRect(
                    x: rightHalf ? rect.midX : rect.minX,
                    y: rect.minY,
                    width: rect.width / 2,
                    height: rect.height
                )))
                skin.draw(layer, rect, rimWidth: rimWidth)
            }

            for offset in 0 ..< pageSlots {
                let slot = firstSlot + offset
                guard slot < total else { break }
                let p = kotekan.polos[slot]
                let s = kotekan.sangsih[slot]

                if let p, p == s {
                    draw(p, slot: offset, skin: .polos, half: true, rightHalf: false)
                    draw(p, slot: offset, skin: .sangsih, half: true, rightHalf: true)
                    continue
                }
                if let p { draw(p, slot: offset, skin: .polos, half: false, rightHalf: false) }
                if let s { draw(s, slot: offset, skin: .sangsih, half: false, rightHalf: false) }
            }
        }
    }

    /// The sweep, alone in its own view and its own layer.
    private struct Playhead: View {
        let engine: PlayEngine

        var body: some View {
            let playhead = engine.playhead
            return Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
                let x = size.width * min(1, max(0, playhead))
                ctx.fill(
                    Path(CGRect(x: x - 0.75, y: 0, width: 1.5, height: size.height)),
                    with: .color(Theme.cream.opacity(0.85))
                )
            }
        }
    }
}

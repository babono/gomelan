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
            let blockH = max(3, lane - 2)
            let blockW = max(3, slotW * 0.82)

            func y(_ key: Int) -> CGFloat {
                size.height - CGFloat(key - range.lowerBound + 1) * lane + (lane - blockH) / 2
            }

            func draw(_ key: Int, slot: Int, color: Color, half: Bool, rightHalf: Bool) {
                let rect = CGRect(
                    x: CGFloat(slot) * slotW,
                    y: y(key),
                    width: blockW,
                    height: blockH
                )
                let block = Path(roundedRect: rect, cornerRadius: 1.5)
                guard half else { ctx.fill(block, with: .color(color))
                    return
                }
                var layer = ctx
                layer.clip(to: Path(CGRect(
                    x: rightHalf ? rect.midX : rect.minX,
                    y: rect.minY,
                    width: rect.width / 2,
                    height: rect.height
                )))
                layer.fill(block, with: .color(color))
            }

            for offset in 0 ..< pageSlots {
                let slot = firstSlot + offset
                guard slot < total else { break }
                let p = kotekan.polos[slot]
                let s = kotekan.sangsih[slot]

                if let p, p == s {
                    draw(p, slot: offset, color: Theme.polosVoice, half: true, rightHalf: false)
                    draw(p, slot: offset, color: Theme.sangsihVoice, half: true, rightHalf: true)
                    continue
                }
                if let p { draw(p, slot: offset, color: Theme.polosVoice, half: false, rightHalf: false) }
                if let s { draw(s, slot: offset, color: Theme.sangsihVoice, half: false, rightHalf: false) }
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

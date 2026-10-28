//
//  VoiceSkin.swift
//  Kotek
//
//  A voice's block, from the design drawing (`polos-on`, `sangsih-on`):
//  lighter at the top, a brighter rim. (`polos-mute` and `sangsih-mute`, the
//  half you are not playing, went when the waterfall stopped drawing it.) Shared
//  by the waterfall and the picker cards' mini score so a figure looks the
//  same before you pick it as it does while you play it.
//

import SwiftUI

struct VoiceSkin {
    var top: Color, bottom: Color, rim: Color

    /// Not `Theme.polosVoice`/`sangsihVoice` — the drawing deepens both so
    /// they sit on the warm ground without glowing.
    static let polos = VoiceSkin(
        top: Color(hex: 0x678BC6),
        bottom: Color(hex: 0x3E527F),
        rim: Color(hex: 0x7BA2E4)
    )
    /// Darker than `sangsih-on` as drawn (A382C6 → 78529F): on screen that
    /// read paler than polos, its bottom ~45% brighter. These are the drawn
    /// hues scaled to polos's luminance, so the two halves weigh the same.
    static let sangsih = VoiceSkin(
        top: Color(hex: 0x9C7DBE),
        bottom: Color(hex: 0x644486),
        rim: Color(hex: 0xB391D8)
    )
    static let damp = VoiceSkin(
        top: Color(hex: 0x715736),
        bottom: Color(hex: 0x55422D),
        rim: Color(hex: 0x9E7B49)
    )

    static func of(_ half: KotekanHalf) -> VoiceSkin {
        half == .polos ? .polos : .sangsih
    }

    func draw(_ ctx: GraphicsContext, _ r: CGRect, rimWidth: CGFloat = 1.5) {
        let radius = min(r.width, r.height) * 0.22
        let inset = rimWidth / 2
        ctx.fill(Path(roundedRect: r, cornerRadius: radius), with: .linearGradient(
            Gradient(colors: [top, bottom]),
            startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)
        ))
        ctx.stroke(
            Path(roundedRect: r.insetBy(dx: inset, dy: inset), cornerRadius: max(0, radius - inset)),
            with: .color(rim),
            lineWidth: rimWidth
        )
    }
}

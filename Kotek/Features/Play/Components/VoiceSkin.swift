//
//  VoiceSkin.swift
//  Kotek
//
//  A voice's block on the picker cards' mini score: a fill and a rim. It was
//  shared with the waterfall, whose blocks were shaded — lighter at the top,
//  a brighter rim (`polos-on`, `sangsih-on`) — until the designer's waterfall
//  (November 2026) drew flat pills in the voice colours instead.
//

import SwiftUI

struct VoiceSkin {
    var top: Color, bottom: Color, rim: Color

    /// The picker card's score: polos a solid Merah tile, sangsih a solid
    /// blue one — flat, because at a 7pt tile the shading was mud. Sangsih was
    /// first white ringed in blue, as the design system drew it; beside solid
    /// Merah it read as a gap, a note not there.
    static let polosCard = VoiceSkin(top: Theme.merah, bottom: Theme.merah, rim: Theme.merah)
    static let sangsihCard = VoiceSkin(top: Theme.sangsihBlue, bottom: Theme.sangsihBlue, rim: Theme.sangsihBlue)

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

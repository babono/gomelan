//
//  PatternBackground.swift
//  Kotek
//
//  The ground every screen sits on: warm brown, with the Kotek pattern tiled
//  over it faintly — see `Theme.patternOpacity` — and drifting diagonally,
//  forever.
//
//  Drawn in a single `Canvas` rather than a stack of `Image` views. The pattern
//  is one tile repeated across the whole screen — at 724x360 that is a dozen or
//  so copies in landscape — and as a ForEach of Images it would be a dozen view
//  identities to diff every frame, behind everything else the app is doing. One
//  draw pass costs the same whether it paints one tile or thirty.
//
//  The loop is seamless because the offset is taken modulo the tile size. The
//  drift is only ever a translation of an already-rendered tile, so there is no
//  per-frame layout, no re-rasterising, and nothing accumulates: at any speed
//  the phase stays inside one tile and the arithmetic cannot drift out of range
//  however long the app is left running.
//

import SwiftUI

struct PatternBackground: View {
    /// Tile size in points: half the artwork's own size, which is the density
    /// the motif was drawn to read at.
    ///
    /// READ FROM THE ASSET, not typed in. This number has been wrong twice
    /// already: the tile was re-exported 1448x720 → 2083x1036 → 1448x720, and a
    /// hardcoded half of the wrong one renders every motif at 69% or 144% of its
    /// intended size — which looks like a design problem rather than a stale
    /// constant, since the aspect ratio is unchanged and nothing is distorted.
    /// Asking the image how big it is cannot go stale.
    static let tileSize: CGSize = {
        guard let intrinsic = UIImage(named: "bg-pattern")?.size, intrinsic.width > 0 else {
            // Only reachable if the asset is missing, in which case there is
            // nothing to draw and the size does not matter.
            return CGSize(width: 724, height: 360)
        }
        return CGSize(width: intrinsic.width / 2, height: intrinsic.height / 2)
    }()

    var tile = PatternBackground.tileSize
    /// Points per second, travelling down-right.
    var speed: Double = 9
    var opacity: Double = Theme.patternOpacity
    /// Set false for screens where the ground is a live camera image.
    var showsGround = true

    var body: some View {
        // Capped at 30fps rather than following the display link. At 9pt/s the
        // pattern moves less than a third of a point between frames at 120Hz —
        // invisible, and it would be redrawing every tile to achieve it. This is
        // ambient decoration and must never compete with the play loop.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // Modulo keeps the phase inside a single tile, so the motion is
            // continuous but the number fed to the renderer never grows.
            let phaseX = (t * speed).truncatingRemainder(dividingBy: tile.width)
            let phaseY = (t * speed).truncatingRemainder(dividingBy: tile.height)

            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                if showsGround {
                    context.fill(Path(CGRect(origin: .zero, size: size)),
                                 with: .color(Theme.ground))
                }
                guard let symbol = context.resolveSymbol(id: 0) else { return }

                context.opacity = opacity
                // Start one tile off-screen on each axis so the leading edge is
                // always covered as the phase advances.
                var y = phaseY - tile.height
                while y < size.height {
                    var x = phaseX - tile.width
                    while x < size.width {
                        context.draw(symbol,
                                     in: CGRect(x: x, y: y,
                                                width: tile.width, height: tile.height))
                        x += tile.width
                    }
                    y += tile.height
                }
            } symbols: {
                Image("bg-pattern")
                    .resizable()
                    .tag(0)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Convenience

extension View {
    /// Put the Kotek ground behind this view.
    ///
    /// `ignoresSafeArea` is applied inside the background so the pattern reaches
    /// the edges without the content having to.
    func kotekGround() -> some View {
        background(PatternBackground())
    }

    /// The pattern alone, for screens whose ground is the camera feed. Laid over
    /// the preview at a lower strength so it reads as a tint rather than
    /// competing with the instrument.
    func kotekPatternOverlay(opacity: Double = 0.06) -> some View {
        overlay(PatternBackground(opacity: opacity, showsGround: false))
    }
}

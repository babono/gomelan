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
//  identities to diff. One draw pass costs the same whether it paints one tile
//  or thirty.
//
//  IT DRAWS ONCE. The canvas used to live inside a `TimelineView(.animation)`
//  and repaint at 30fps forever, with the phase folded into the tile origins.
//  That is a full-screen fill plus nine large blits, thirty times a second, on
//  every non-camera screen in the app — and it measured on device at GPU 54% /
//  CPU 32% with the phone sitting on the landing screen doing nothing at all.
//  Ambient decoration was the most expensive thing running.
//
//  So the drift is a Core Animation translation of a canvas that never
//  repaints: one tile larger than the screen on each axis, slid from -tile to 0
//  by a `repeatForever` linear animation. The render server interpolates the
//  transform and the app process does no work per frame. The loop is seamless
//  for the same reason it always was — the pattern is periodic in one tile, so
//  offset 0 and offset -tile are the same picture and the wrap is invisible.

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

    /// Flipped once, on appear. Everything after that happens on the render
    /// server: `repeatForever` keeps the transform moving with no further help
    /// from SwiftUI, so leaving a screen up costs nothing.
    @State private var drifted = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if showsGround { Theme.ground }

                //R One tile of slack on each axis, so the visible window stays
                //R covered at both ends of the travel: at offset 0 by the tiles
                //R starting at the origin, and at -tile by the ones after them.
                tiles
                    .frame(width: geo.size.width + tile.width,
                           height: geo.size.height + tile.height,
                           alignment: .topLeading)
                    .opacity(opacity)
                    .offset(x: drifted ? 0 : -tile.width,
                            y: drifted ? 0 : -tile.height)
                    //R Both axes wrap on ONE duration, so a single value drives
                    //R the whole drift. The tile is wider than it is tall, so
                    //R this travels at a shallower angle than the old
                    //R equal-speed diagonal — on decoration moving nine points
                    //R a second, past caring.
                    .animation(.linear(duration: tile.width / speed)
                                .repeatForever(autoreverses: false),
                               value: drifted)
            }
            .clipped()
            .onAppear { drifted = true }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    /// The tiled field, painted once. No phase in here: the drift is a transform
    /// applied to the result, which is exactly what keeps this closure from
    /// being called again.
    private var tiles: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            guard let symbol = context.resolveSymbol(id: 0) else { return }
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
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

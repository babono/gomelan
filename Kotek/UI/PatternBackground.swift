//
//  PatternBackground.swift
//  Kotek
//
//  The ground every screen sits on: warm brown, with the gamelan pattern tiled
//  over it faintly — see `Theme.patternOpacity` — and drifting diagonally,
//  forever.
//
//  The tile is a raster (`bg-pattern-gamelan.png`) where it used to be a vector
//  (`bg-pattern.svg`). Nothing about the drift changes; the two differences that
//  do matter are recorded on `tileSize` (the artwork is now drawn at 1:1, so it
//  is no longer halved) and on `Theme.patternOpacity` (the fade is baked into
//  the PNG's alpha, so the view lays it in at full strength).
//
//  Drawn in a single `Canvas` rather than a stack of `Image` views. The pattern
//  is one tile repeated across the whole screen — at 724x402 that is a dozen or
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
    /// Tile size in points: the artwork's own size, which is the density the
    /// motif was drawn to read at.
    ///
    /// READ FROM THE ASSET, not typed in. This number has been wrong twice
    /// already: the old vector tile was re-exported 1448x720 → 2083x1036 →
    /// 1448x720, and a hardcoded fraction of the wrong one renders every motif
    /// at 69% or 144% of its intended size — which looks like a design problem
    /// rather than a stale constant, since the aspect ratio is unchanged and
    /// nothing is distorted. Asking the image how big it is cannot go stale.
    ///
    /// No halving any more. The vector tile was drawn at 2x and displayed at
    /// half size (1448x720 → 724x360); the gamelan raster is already drawn at
    /// the size it is meant to be seen at, and the imageset declares it single
    /// scale, so its intrinsic size in points *is* the tile — 724x402, near
    /// enough the same field as before.
    static let tileSize: CGSize = {
        guard let intrinsic = UIImage(named: assetName)?.size, intrinsic.width > 0 else {
            // Only reachable if the asset is missing, in which case there is
            // nothing to draw and the size does not matter.
            return CGSize(width: 724, height: 402)
        }
        return intrinsic
    }()

    /// One name, used by both the size probe and the draw. They must not drift.
    static let assetName = "bg-pattern-gamelan"

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
            Image(PatternBackground.assetName)
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
    /// competing with the instrument — three quarters of the tile's own
    /// strength, which is where the old 0.06-against-0.08 sat.
    func kotekPatternOverlay(opacity: Double = 0.75) -> some View {
        overlay(PatternBackground(opacity: opacity, showsGround: false))
    }
}

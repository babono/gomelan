//
//  PuraGate.swift
//  Kotek
//
//  The split gate (candi bentar) the splash pans down to, and that opens on
//  the landing screen. One half is the artwork (`pura-gate`, the RIGHT half:
//  its dark inner post is on its left); the left half is the same file
//  mirrored, as the real gate is.
//
//  Shared by the splash and the landing screen ON PURPOSE, for the same reason
//  `KotekWordmark` used to be: the splash opens its gate over the landing
//  screen, which draws its own, already open, in the same place — so when the
//  splash goes, nothing moves. Both copies have to agree on the geometry to
//  the point, which they can only do if it lives in one place.
//
//  Every number is read off the designer's mockups (iPhone 17, 874 x 402
//  landscape) and scaled by `LaunchLayout.unit`.
//

import SwiftUI

struct PuraGate: View, Animatable {
    /// How far the approach has gone. 0: shut, and seen from a little way
    /// off (`farZoom`) — the splash arrives on it like that. 1: open, its
    /// halves drawn back to the screen's edges with a strip of each still
    /// showing, at the landing mockup's size — where the landing screen has it.
    ///
    /// ONE number, animated, rather than an open flag and a zoom animated side
    /// by side. SwiftUI interpolates the offsets it is handed in a straight
    /// line between their ends, and a half that slides while the camera
    /// zooms does not travel in one: the splash's gate fell behind the landing
    /// screen's (which only zooms), and showed it, a second gate inside the
    /// first, through the opening. Here every frame is worked out from
    /// `progress`, so the splash's halves are always inside the landing's.
    var progress: CGFloat
    /// Paper behind each half, out to its own edge of the screen, so a CLOSED
    /// gate hides whatever is behind it and opening it reveals that through
    /// the widening gap. The splash's gate is walled; the landing screen's is
    /// not — it IS what is behind.
    var walled = false

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// How far off the gate is at the start of the approach: small enough
    /// that the whole of it, spires and all, stands on screen with sky above.
    /// The landing screen is drawn at this size behind it (`WelcomeView.zoom`),
    /// and both grow to 1 together.
    static let farZoom: CGFloat = 0.78

    /// `pura-gate`'s own size. Drawn at 1x in both mockups.
    static let art = CGSize(width: 208, height: 434)
    /// Daylight between the closed halves.
    private static let closedGap: CGFloat = 17
    /// Where an open half's inner post stands, from its own edge of the screen.
    private static let openInset: CGFloat = 86
    /// How far the gate hangs below the bottom edge — closed it is
    /// bottom-aligned; open, the landing mockup has it 16pt lower, so it
    /// settles a touch as it swings back.
    private static let openDrop: CGFloat = 16

    /// The clear width between the open gate's posts, on a screen this size —
    /// what the landing screen's gangsa has to fit inside.
    static func openingWidth(in size: CGSize) -> CGFloat {
        size.width - 2 * openInset * LaunchLayout.unit(in: size)
    }

    /// The camera: below 1 the whole gate is drawn smaller about the middle
    /// of the bottom edge. The walls are NOT scaled — they always run out to
    /// the screen's edges, so a distant gate still hides what is behind it.
    private var zoom: CGFloat {
        Self.farZoom + (1 - Self.farZoom) * progress
    }

    /// Drawn in a Canvas, not as images with offsets. As views, each half and
    /// its wall were children that SwiftUI animated AGAIN on every frame of
    /// `progress` — each new offset handed the same 1.8s curve from wherever
    /// the last frame left it — so they lagged, each by its own amount, and
    /// the landing screen's gate showed between the splash's halves and their
    /// walls. A Canvas has no children: each frame is drawn from `progress`
    /// and nothing else.
    var body: some View {
        Canvas { context, size in
            let u = LaunchLayout.unit(in: size)
            let gate = context.resolve(Image("pura-gate"))
            let art = CGSize(width: Self.art.width * u * zoom, height: Self.art.height * u * zoom)
            // Each half's inner edge, as a distance from the centre line.
            let shut = Self.closedGap / 2 * u
            let inner = shut + (size.width / 2 - Self.openInset * u - shut) * progress
            let top = seen(y: size.height - (Self.art.height - Self.openDrop * progress) * u, size: size)

            for side: CGFloat in [-1, 1] {
                // The inner post's x on screen.
                let edge = seen(x: size.width / 2 + side * inner, size: size)
                if walled {
                    // From the screen's edge to the middle of the closed gap —
                    // past the post by half the gap — so the closed gate shows
                    // no slit of the landing screen between its halves. And a
                    // point past that: two walls meeting exactly on a
                    // fractional pixel leave an antialiased hairline, and the
                    // wordmark's red showed through it.
                    //
                    // Only while it is shut. The overlap draws back as the
                    // gate opens, until, fully open, the wall ends a point
                    // UNDER the post. Held at its full width, it left a strip
                    // of bare paper inside each post, over the landing screen,
                    // that only went when the splash faded at the very end.
                    let closed = 1 - progress
                    let past = (shut * zoom + 1) * closed - progress
                    let wall = edge - side * past
                    let rect = side < 0
                        ? CGRect(x: 0, y: 0, width: wall, height: size.height)
                        : CGRect(x: wall, y: 0, width: size.width - wall, height: size.height)
                    context.fill(Path(rect), with: .color(Theme.paper))
                }
                // The artwork is the RIGHT half; the left is it mirrored about
                // its post.
                var half = context
                half.translateBy(x: edge, y: top)
                half.scaleBy(x: side, y: 1)
                half.draw(gate, in: CGRect(origin: .zero, size: art))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Laid out at zoom 1, then moved to where the camera sees it: about the
    /// middle of the bottom edge, the same anchor the landing screen zooms
    /// about, so the gate and what is behind it approach together.
    /// Worked out here rather than with a `scaleEffect` because the walls
    /// must not shrink with it.
    private func seen(x: CGFloat, size: CGSize) -> CGFloat {
        size.width / 2 + (x - size.width / 2) * zoom
    }

    private func seen(y: CGFloat, size: CGSize) -> CGFloat {
        size.height + (y - size.height) * zoom
    }
}

//
//  PatternBackground.swift
//  Kotek
//
//  The ground every screen sits on: warm brown, and across it one row of the
//  carved-leaf motif — each 90% of the screen tall, every other one turned
//  upside down, so they interlock like a row of teeth — running slowly to the
//  right, forever, like a marquee.
//
//  The motif (`bg-motif`, from the October 2026 revamp) is ONE outline leaf,
//  wide at the top and tapering to a point. Hanging from the top edge it
//  points down; flipped and standing on the bottom edge it points up; half a
//  leaf apart, each fills the gap the other's taper leaves. It is a template
//  image, so its colour is `Theme.pattern` — the asset catalog's.
//
//  Core Animation, not SwiftUI: each row's period is drawn into a bitmap
//  once, and a `Marquee` repeats that texture across the screen and slides it
//  on the render server. This used to be a Canvas moved
//  by a SwiftUI `repeatForever` offset, on the belief that the render server
//  interpolated it. It does not: SwiftUI computes each frame of its own
//  animations on the main thread, so the "free" background was a per-frame
//  cost on every screen, and stuttered whenever the main thread was busy.

import SwiftUI

struct PatternBackground: View {
    /// One name, used by both the size probe and the draw. They must not drift.
    static let assetName = "bg-motif"

    /// The artwork's proportions, read from the asset rather than typed in —
    /// a hardcoded size has gone stale in this file twice before.
    private static let motifAspect: CGFloat = {
        guard let size = UIImage(named: assetName)?.size, size.height > 0 else { return 212.0 / 364.0 }
        return size.width / size.height
    }()

    /// Each leaf's height, as a share of the screen's.
    private static let heightFraction: CGFloat = 0.9

    /// Points per second, travelling right.
    var speed: Double = 9
    var opacity: Double = Theme.patternOpacity
    /// Set false for screens where the ground is a live camera image.
    var showsGround = true

    /// False keeps the leaves off screen. Turned true, they arrive — the
    /// hanging ones down from the top, the upturned ones up from the bottom —
    /// and only then start to move across. Launch holds them back until the
    /// splash's curtains are gone, which is both the grander entrance and two
    /// fewer things to draw behind the splash.
    private let shown: Bool
    @State private var entered: Bool
    @State private var running = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(speed: Double = 9, opacity: Double = Theme.patternOpacity, showsGround: Bool = true, shown: Bool = true) {
        self.speed = speed
        self.opacity = opacity
        self.showsGround = showsGround
        self.shown = shown
        _entered = State(initialValue: shown)
    }

    /// How long the leaves take to come in from the edges.
    private static let entrance = 0.9

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let period = height * Self.heightFraction * Self.motifAspect
            let count = Int((geo.size.width / period).rounded(.up)) + 2
            ZStack {
                if showsGround { Theme.ground }
                if height > 0 {
                    // Two rows, one texture each, sliding on one clock: they
                    // start in the same transaction with the same duration, so
                    // the teeth stay interlocked however long the screen is up.
                    ForEach([true, false], id: \.self) { hanging in
                        Marquee(
                            image: Self.row(hanging: hanging, height: height),
                            origin: .zero,
                            spacing: CGVector(dx: period, dy: 0),
                            count: count,
                            travel: CGVector(dx: period, dy: 0),
                            duration: period / speed,
                            // Still, with Reduce Motion on: ambient movement is
                            // exactly what that setting asks apps to leave out.
                            running: running && !reduceMotion,
                            placement: entered
                                ? CATransform3DIdentity
                                : Marquee.shifted(CGVector(dx: 0, dy: hanging ? -height : height)),
                            placementDuration: Self.entrance
                        )
                    }
                    .opacity(opacity)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear { if entered { running = true } }
        .onChange(of: shown) { _, now in
            guard now, !entered else { return }
            entered = true
            Task {
                try? await Task.sleep(for: .seconds(Self.entrance))
                running = true
            }
        }
    }

    /// One period of one row, for a screen this tall. The hanging row is a
    /// leaf from the top at the left edge; the standing row is the upturned
    /// leaves either side of it, cut at the edges so the copies join without
    /// a seam. Drawn once per height.
    private static func row(hanging: Bool, height: CGFloat) -> UIImage {
        let key = "\(hanging)-\(height)"
        if let cached = cache[key] { return cached }
        let motif = CGSize(width: height * heightFraction * motifAspect, height: height * heightFraction)
        let leaf = UIImage(named: assetName)?
            .withTintColor(UIColor(named: "PatternBackground") ?? .brown, renderingMode: .alwaysOriginal)
        let image = Marquee.render(size: CGSize(width: motif.width, height: height)) { cg in
            if hanging {
                leaf?.draw(in: CGRect(origin: .zero, size: motif))
            } else {
                // Turned over and stood on the bottom edge, half a leaf either side.
                cg.translateBy(x: 0, y: height)
                cg.scaleBy(x: 1, y: -1)
                for x in [-motif.width / 2, motif.width / 2] {
                    leaf?.draw(in: CGRect(origin: CGPoint(x: x, y: 0), size: motif))
                }
            }
        }
        cache[key] = image
        return image
    }

    private nonisolated(unsafe) static var cache: [String: UIImage] = [:]
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

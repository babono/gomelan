//
//  SplashView.swift
//  Kotek
//
//  The launch screen (the October 2026 revamp): the wordmark and its script,
//  the loading line, and the gangsa playing along the foot — between two
//  diagonal strips of carved flowers, each sliding down its own diagonal like
//  a marquee from the first frame. When loading is done they swell outwards
//  off the screen and the splash hands over to the landing screen
//  underneath.
//
//  The wordmark and the gangsa are NOT animated out. The landing screen draws
//  both in the same place (`LaunchStage`), and the gangsa is a pure function
//  of the clock, so the two copies show the same frame: when the splash's
//  ground fades and it is removed, nothing in the middle of the screen moves.
//
//  The Mekar Bhuana credit and the "Built at" line that sat under the old
//  pill are gone from here — the design has the gangsa there now. Mekar
//  Bhuana is still on the landing screen, top right.
//

import SwiftUI

struct SplashView: View {
    /// 0…1. Drives the loading line.
    var progress: Double
    /// Loading is done: part the curtains.
    var finished: Bool
    /// Loading is done and the curtains are opening. The landing screen
    /// underneath starts its own gangsa from here — see `LaunchStage`.
    var onOpen: () -> Void = {}
    /// Off screen; remove the splash.
    var onDone: () -> Void

    @State private var parted = false

    /// Seconds for the curtains to clear the screen.
    private static let partDuration = 0.8

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                Theme.ground
                    .opacity(parted ? 0 : 1)
                    .animation(.easeOut(duration: 0.5).delay(0.3), value: parted)

                // Behind the stage: the table's posts stand in front of them.
                CurtainColumn(side: .leading, screen: size, parted: parted)
                CurtainColumn(side: .trailing, screen: size, parted: parted)

                LaunchStage {
                    LoadingBar(progress: progress)
                        .frame(width: min(240, size.width * 0.25), height: 5)
                        .padding(.top, size.height * 0.04)
                        .opacity(parted ? 0 : 1)
                        .animation(.easeOut(duration: 0.25), value: parted)
                }
                // Held a touch small while loading, and eased up to full size
                // as the curtains open — finishing well before the hand-over,
                // so it meets the landing screen's copy at exactly 1.
                .scaleEffect(parted ? 1 : 0.95)
                .animation(.easeOut(duration: 0.6), value: parted)
            }
        }
        .ignoresSafeArea()
        .onChange(of: finished, initial: true) { _, done in
            if done { part() }
        }
    }

    private func part() {
        guard !parted else { return }
        parted = true
        onOpen()
        Task {
            try? await Task.sleep(for: .seconds(Self.partDuration * 1.1))
            onDone()
        }
    }
}

/// One side's ornament: a band of the carved motif (`splash-motif`, solid),
/// laid at a slant, sliding down its own diagonal — the left one towards the
/// bottom left, the right one towards the bottom right — like a marquee, in
/// Core Animation (`Marquee`).
///
/// The band is built here from ONE motif, the same way the background builds
/// its rows: a row hanging and a row standing, half a motif apart. The first
/// design shipped each strip as a ready-drawn file with its unit spacing and
/// anchor typed in from the artwork, so a redrawn motif meant re-measuring
/// both; from one tile, a redraw is a file swap.
///
/// Every unit sits exactly one `step` from the next, so copies laid end to
/// end make one endless strip, and sliding it by one step lands every unit
/// where its neighbour was: the loop is invisible. On `parted` the strip
/// swings out about its outer edge, growing as it goes, until it is off the
/// screen.
private struct CurtainColumn: View {
    let side: HorizontalEdge
    let screen: CGSize
    let parted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Up the strip: one across for two up, the slant the first design's
    /// strips had. The right strip runs the other way across.
    private static let run = CGVector(dx: 1, dy: -2)
    /// Each motif's height, as a share of the screen's — so the band is the
    /// same share of the screen on every phone (and on iPad, before PadScale),
    /// and about as wide as the first design's.
    private static let motifShare: CGFloat = 0.47
    /// The design's proportions, as in `PatternBackground`: neighbours 6.5%
    /// of a width apart, the band 1.2 motifs deep.
    private static let pitch: CGFloat = 1.065
    private static let depth: CGFloat = 1.2
    /// Units drawn into one copy of the strip.
    private static let units = 6
    /// Points per second along the diagonal.
    private static let speed: Double = 16

    var body: some View {
        let leading = side == .leading
        let strip = Self.strip(leading: leading, screenHeight: screen.height)
        let target = CGPoint(x: screen.width * (leading ? 0.13 : 0.87), y: screen.height * 0.2)
        let origin = CGPoint(x: target.x + strip.offset.dx, y: target.y + strip.offset.dy)
        let step = strip.step

        Marquee(
            image: strip.image,
            origin: origin,
            spacing: CGVector(dx: step.dx * CGFloat(Self.units), dy: step.dy * CGFloat(Self.units)),
            // One copy on screen, one either side up the strip, one below.
            count: 4,
            // Down the diagonal by one unit, over and over.
            travel: CGVector(dx: -step.dx, dy: -step.dy),
            duration: hypot(step.dx, step.dy) / Self.speed,
            running: !reduceMotion,
            // Swung outwards — the left strip anticlockwise, the right
            // clockwise, each about its own bottom corner — and grown, as if
            // the curtains were drawn back past the audience, sliding until it
            // clears the glass.
            placement: parted
                ? Marquee.swung(
                    about: CGPoint(x: leading ? 0 : screen.width, y: screen.height),
                    in: screen,
                    degrees: leading ? -38 : 38,
                    scale: 1.6,
                    then: CGVector(dx: (leading ? -1 : 1) * screen.width * 0.55, dy: 0)
                )
                : CATransform3DIdentity,
            placementDuration: 0.8,
            placementTiming: .easeIn
        )
        .frame(width: screen.width, height: screen.height)
        .allowsHitTesting(false)
    }

    /// One copy of the strip, drawn once at its on-screen size, for the
    /// marquee to repeat.
    private struct Strip {
        let image: UIImage
        /// From the topmost unit's centre — the point placed on screen — to
        /// the image's top-left corner.
        let offset: CGVector
        /// One unit up the strip.
        let step: CGVector
    }

    /// Laid out flat — x along the band, y across it from the hanging row's
    /// edge — then turned onto the slant as it is drawn. The right strip is
    /// the left one mirrored; the motif is symmetric, so only the slant shows
    /// it. Cached: a new bitmap on every SwiftUI update would restart the slide.
    private static func strip(leading: Bool, screenHeight: CGFloat) -> Strip {
        let key = "\(leading)@\(screenHeight)"
        if let cached = cache[key] { return cached }
        let art = UIImage(named: "splash-motif")
        let aspect = art.map { $0.size.width / $0.size.height } ?? 342.0 / 424.0
        let motif = CGSize(width: screenHeight * motifShare * aspect, height: screenHeight * motifShare)
        let period = motif.width * pitch

        let length = hypot(run.dx, run.dy)
        let along = CGVector(dx: (leading ? run.dx : -run.dx) / length, dy: run.dy / length)
        let across = CGVector(dx: leading ? -along.dy : along.dy, dy: leading ? along.dx : -along.dx)
        let slant = CGAffineTransform(a: along.dx, b: along.dy, c: across.dx, d: across.dy, tx: 0, ty: 0)

        let last = CGFloat(units - 1) * period
        let flat = CGRect(
            x: -motif.width / 2, y: 0,
            width: last + period / 2 + motif.width, height: motif.height * depth
        )
        let bounds = flat.applying(slant)
        let image = Marquee.render(size: bounds.size) { cg in
            cg.translateBy(x: -bounds.minX, y: -bounds.minY)
            cg.concatenate(slant)
            for i in 0 ..< units {
                let x = CGFloat(i) * period
                // Hanging: turned over, fan on the band's top edge.
                cg.saveGState()
                cg.translateBy(x: x - motif.width / 2, y: motif.height)
                cg.scaleBy(x: 1, y: -1)
                art?.draw(in: CGRect(origin: .zero, size: motif))
                cg.restoreGState()
                // Standing: upright, half a period on, fan on the bottom edge.
                let foot = CGPoint(x: x + period / 2 - motif.width / 2, y: motif.height * (depth - 1))
                art?.draw(in: CGRect(origin: foot, size: motif))
            }
        }
        let top = CGPoint(x: last + period / 4, y: motif.height * depth / 2).applying(slant)
        let strip = Strip(
            image: image,
            offset: CGVector(dx: bounds.minX - top.x, dy: bounds.minY - top.y),
            step: CGVector(dx: along.dx * period, dy: along.dy * period)
        )
        cache[key] = strip
        return strip
    }

    private nonisolated(unsafe) static var cache: [String: Strip] = [:]
}

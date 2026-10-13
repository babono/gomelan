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

/// One side's ornament: the designers' strip of flower-and-fern units
/// (`splash-ornament-left` / `-right`), drawn at its own angle, sliding down
/// its own diagonal — the left one towards the bottom left, the right one
/// towards the bottom right — like a marquee, in Core Animation (`Marquee`).
///
/// Each file is six units long in two staggered lanes, and every unit sits
/// exactly one `step` from the next (72 across, 144 down, in the artwork's
/// units). So copies laid end to end six steps apart make one endless strip,
/// and sliding it by one step lands every unit where its neighbour was: the
/// loop is invisible. On `parted` the strip swings out about its outer edge,
/// growing as it goes, until it is off the screen.
private struct CurtainColumn: View {
    let side: HorizontalEdge
    let screen: CGSize
    let parted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Both files are 693 x 1032.
    private static let artSize = CGSize(width: 693, height: 1032)
    /// One unit up the strip, artwork units. The right strip runs the other
    /// way across.
    private static let stepAcross: CGFloat = 72
    private static let stepUp: CGFloat = 144
    private static let unitsPerFile = 6
    /// The topmost unit's centre in each file — the point placed on screen.
    private static let leftTop = CGPoint(x: 567, y: 155)
    private static let rightTop = CGPoint(x: 126, y: 155)
    /// Points per second along the diagonal.
    private static let speed: Double = 16

    var body: some View {
        let leading = side == .leading
        // Sized to the screen's height, so a unit is the same share of the
        // screen on every phone (and on iPad, before PadScale).
        let s = screen.height / 402 * 0.87
        let art = CGSize(width: Self.artSize.width * s, height: Self.artSize.height * s)
        let step = CGSize(width: (leading ? Self.stepAcross : -Self.stepAcross) * s, height: -Self.stepUp * s)
        let period = CGSize(
            width: step.width * CGFloat(Self.unitsPerFile),
            height: step.height * CGFloat(Self.unitsPerFile)
        )
        let anchor = leading ? Self.leftTop : Self.rightTop
        let target = CGPoint(x: screen.width * (leading ? 0.22 : 0.78), y: screen.height * 0.2)
        let origin = CGPoint(x: target.x - anchor.x * s, y: target.y - anchor.y * s)

        Marquee(
            image: Self.strip(leading: leading, size: art),
            origin: origin,
            spacing: CGVector(dx: period.width, dy: period.height),
            // One copy on screen, one either side up the strip, one below.
            count: 4,
            // Down the diagonal by one unit, over and over.
            travel: CGVector(dx: -step.width, dy: -step.height),
            duration: hypot(step.width, step.height) / Self.speed,
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

    /// The SVG drawn once at its on-screen size, for the marquee to repeat.
    /// Cached: a new bitmap on every SwiftUI update would restart the slide.
    private static func strip(leading: Bool, size: CGSize) -> UIImage {
        let name = leading ? "splash-ornament-left" : "splash-ornament-right"
        let key = "\(name)@\(size.width)x\(size.height)"
        if let cached = cache[key] { return cached }
        let art = UIImage(named: name)
        let image = Marquee.render(size: size) { _ in
            art?.draw(in: CGRect(origin: .zero, size: size))
        }
        cache[key] = image
        return image
    }

    private nonisolated(unsafe) static var cache: [String: UIImage] = [:]
}

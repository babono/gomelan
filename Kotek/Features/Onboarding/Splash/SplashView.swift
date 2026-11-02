//
//  SplashView.swift
//  Kotek
//
//  The launch screen (the November 2026 redesign), in three beats:
//
//   1. Loading. Kipli, the mascot, chomps in front of the nawa sanga — the
//      eight-petalled rose of the Balinese directions — turning slowly behind
//      him. (A short loading line sat under his chin until November 2026; it
//      was paced to look busy and kept the splash up for over four seconds.)
//   2. The camera pans down. Kipli and the rose slide up and away; from
//      below rises a split gate (candi bentar), shut, whole, and small — seen
//      from a little way off. The rose is cut by the screen's bottom edge
//      but not ended there: its lower petals run on below it, so the pan
//      travels down through the rose rather than from one picture to the
//      next — and on past it, over a strip of bare paper (`gap`), so where
//      the pan stops none of it is left on screen. (First the gate's screen
//      sat straight under Kipli's, and the petals hung over its top.)
//   3. The camera walks up to it as it opens: the gate grows and its halves
//      draw back to the screen's edges, and through the widening gap is the
//      landing screen, growing with it (the same `PuraGate.farZoom`, in the
//      same animation — see `onOpen` and `WelcomeView.zoom`).
//
//  It replaced the brown splash's two diagonal strips of carved flowers that
//  swung out like curtains.
//
//  The splash sits OVER the landing screen, as before, and is removed only
//  when the gate is fully open. The landing screen draws the same gate,
//  already open, in the same place (`PuraGate`) — from `onArrive`, once the
//  approach is over — so what is under the splash's gate at that moment is an
//  identical gate: the splash fades its copy out over it, and nothing moves. The fade is for first launch, when
//  the introduction is laid over the landing screen and there is no second
//  gate underneath — there, the gate dissolves instead of vanishing.
//
//  The pan and the gate are plain SwiftUI animations. Loading is done by
//  then, so the main thread is free. What moves DURING loading is in Core
//  Animation — Kipli's jaw (`KipliMascot`) and the rose's turn (`NawaSanga`)
//  — and is handed to SwiftUI before the pan, because SwiftUI does not carry
//  a UIKit-backed view along with an animated offset. (The rose turned in
//  SwiftUI at first, on the grounds that loading is only sample decodes now,
//  off the main thread. It stuttered.)
//

import SwiftUI
import UIKit

struct SplashView: View {
    /// Loading is done: pan down and open the gate.
    var finished: Bool
    /// The gate is starting to open. Called INSIDE the opening animation's
    /// transaction, so whatever the caller changes here moves with the gate:
    /// RootView lifts `splashCovering`, which brings the landing screen from
    /// `PuraGate.farZoom` up to full size (`WelcomeView.zoom`) and starts its
    /// gangsa, so it is already playing as it comes into view.
    var onOpen: () -> Void = {}
    /// The gate is fully open and the camera has arrived, just before the
    /// splash fades: the landing screen can draw its own gate now, under this
    /// one's identical last frame.
    var onArrive: () -> Void = {}
    /// Fully open and faded; remove the splash.
    var onDone: () -> Void

    private enum Beat: Int, Comparable {
        case loading, settling, panned, opened, gone

        static func < (a: Beat, b: Beat) -> Bool {
            a.rawValue < b.rawValue
        }
    }

    @State private var beat = Beat.loading

    /// Seconds for the camera to pan from Kipli down to the gate. 1.2 when
    /// the gate's screen sat straight under his; the gap made the pan longer.
    private static let panDuration = 1.4
    /// Bare paper between Kipli's screen and the gate's, in the mockup's
    /// units: room for the rose's lower petals, which reach about 88 below
    /// his screen whichever way it has turned.
    private static let gap: CGFloat = 100
    /// Seconds to walk up to the gate as it swings open. Slow to start, like
    /// a first step, and a long ease at the end as the camera arrives.
    private static let openDuration = 1.8
    private static let approach = Animation.timingCurve(0.45, 0, 0.2, 1, duration: openDuration)
    /// Seconds to fade the splash's gate over the landing screen's.
    private static let fadeDuration = 0.3

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let u = LaunchLayout.unit(in: size)

            // From the top of Kipli's screen to the top of the gate's.
            let drop = size.height + Self.gap * u
            ZStack(alignment: .topLeading) {
                // Below the mascot, past the gap. Drawn under it, so nothing
                // of the gate can show on the mascot's screen.
                PuraGate(progress: beat >= .opened ? 1 : 0, walled: true)
                    .frame(width: size.width, height: size.height)
                    .offset(y: beat >= .panned ? 0 : drop)

                mascot(size: size, u: u)
                    .offset(y: beat >= .panned ? -drop : 0)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .opacity(beat >= .gone ? 0 : 1)
        }
        .ignoresSafeArea()
        .onChange(of: finished, initial: true) { _, done in
            if done { reveal() }
        }
    }

    /// Kipli before the rose: a screen, and the gap
    /// below it that the rose's lower petals run on into. Its paper fills the
    /// gap too — under the splash is the landing screen.
    private func mascot(size: CGSize, u: CGFloat) -> some View {
        let head = KipliMascot.headSize
        return ZStack(alignment: .topLeading) {
            Theme.paper
            NawaSanga(onServer: beat == .loading, still: beat >= .opened)
                .frame(width: NawaSanga.art.width * u, height: NawaSanga.art.height * u)
                .position(x: size.width / 2, y: NawaSanga.centreY * u)
            KipliMascot(unit: u, chomping: beat == .loading)
                .offset(x: size.width / 2 - head.width / 2 * u, y: 45 * u)
        }
        .frame(width: size.width, height: size.height + Self.gap * u, alignment: .topLeading)
    }

    private func reveal() {
        guard beat == .loading else { return }
        // The jaw comes to rest; then the pan.
        beat = .settling
        Task {
            try? await Task.sleep(for: .seconds(KipliMascot.settle + 0.1))
            withAnimation(.easeInOut(duration: Self.panDuration)) { beat = .panned }
            // A breath on the distant gate before the approach.
            try? await Task.sleep(for: .seconds(Self.panDuration + 0.3))
            withAnimation(Self.approach) {
                onOpen()
                beat = .opened
            }
            try? await Task.sleep(for: .seconds(Self.openDuration))
            onArrive()
            withAnimation(.easeOut(duration: Self.fadeDuration)) { beat = .gone }
            try? await Task.sleep(for: .seconds(Self.fadeDuration))
            onDone()
        }
    }
}

/// The nawa sanga behind Kipli, turning: the designer's `nawasanga`, at 1x
/// in the mockup, centred on him. It replaced two still rows of the carved
/// motif (`splash-motif`), one hanging from the top edge, one standing on the
/// bottom.
///
/// Turned by Core Animation while loading (`onServer`), then by SwiftUI —
/// see the header. Both work the angle out from the same moment on the same
/// clock (`CACurrentMediaTime`), so the hand-over has no seam: the SwiftUI
/// copy picks up at the angle the server had reached.
private struct NawaSanga: View {
    /// Core Animation turns it; false hands it to SwiftUI, for the pan.
    var onServer: Bool
    /// Off screen now: stop redrawing it.
    var still: Bool

    /// The art's own size.
    static let art = CGSize(width: 540, height: 538)
    /// Its centre, down from the top of the mockup: level with the tips of
    /// its side petals, on Kipli's face.
    static let centreY: CGFloat = 200
    /// Seconds for one turn — slow, so it reads as the rose turning, not as a
    /// spinner.
    static let turn = 18.0

    /// When it started turning.
    @State private var start = CACurrentMediaTime()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Image("nawasanga").resizable()
        } else if onServer {
            TurningRose(start: start)
        } else {
            TimelineView(.animation(paused: still)) { _ in
                Image("nawasanga")
                    .resizable()
                    .rotationEffect(.degrees(Self.angle(since: start)))
            }
        }
    }

    /// Degrees turned, clockwise, at this moment.
    static func angle(since start: CFTimeInterval) -> Double {
        (CACurrentMediaTime() - start) / turn * 360
    }
}

/// The rose turning on the render server, at full rate whatever loading is
/// doing to the main thread.
private struct TurningRose: UIViewRepresentable {
    let start: CFTimeInterval

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(image: UIImage(named: "nawasanga"))
        view.contentMode = .scaleToFill
        view.isUserInteractionEnabled = false
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = 2 * Double.pi
        turn.duration = NawaSanga.turn
        turn.repeatCount = .infinity
        // Kept through a trip to the background, or it would come back still.
        turn.isRemovedOnCompletion = false
        // From `start`, not from whenever this is first drawn, so it agrees
        // with the SwiftUI copy that takes over.
        turn.beginTime = view.layer.convertTime(start, from: nil)
        view.layer.add(turn, forKey: "turn")
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {}
}

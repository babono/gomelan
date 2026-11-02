//
//  Penjor.swift
//  Kotek
//
//  The landing screen's penjor (the designer's, Nov 2026): a bamboo pole
//  standing just inside each half of the open gate, arching in towards the
//  middle, with its sampian — the woven janur ornament — hanging from the
//  arch and swinging a little, as one does in the wind.
//
//  Two pieces of art, `janur-pole` and `janur-hang`, both drawn at 1x in the
//  landing mockup. The art is the RIGHT penjor (its tip points left, to the
//  middle); the left one is it mirrored, as the gate is. The hang is drawn
//  BEHIND the pole, so its tie is tucked under the arch, and the pole's foot
//  stands behind the gate's post — the landing screen draws the gate after.
//
//  Part of what the gate reveals: it is laid out at the landing screen's
//  camera (`WelcomeView.zoom`), so it grows with the wordmark and the gangsa
//  as the splash's gate opens on it.
//
//  An easter egg, too (`HangTilt`): tilt the phone and each sampian keeps
//  hanging towards the real ground, wobbling as it settles; jolt it sideways
//  and they swing, as if the pole had been knocked.
//

import CoreMotion
import SwiftUI

struct Penjor: View {
    /// -1 for the left penjor (mirrored), 1 for the right.
    let side: CGFloat
    /// The landing screen's camera — see `WelcomeView.zoom`.
    let zoom: CGFloat
    /// Seconds for one swing there and back. The two sides are given
    /// different ones so they drift in and out of step, as two things in the
    /// same wind do — in step, they read as one animation mirrored.
    let swingPeriod: Double
    /// Which way down really is — see `HangTilt`.
    let tilt: HangTilt

    @State private var swung = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The art's own sizes.
    private static let pole = CGSize(width: 202, height: 536)
    private static let hang = CGSize(width: 113, height: 275)
    /// Where they stand in the mockup, as a distance in from their own edge
    /// of the screen (to the centre) and up from the bottom (to the top): the
    /// pole's foot runs off the bottom of the screen.
    private static let poleCentreIn: CGFloat = 143
    private static let poleTopUp: CGFloat = 399
    private static let hangCentreIn: CGFloat = 171
    private static let hangTopUp: CGFloat = 380
    /// How far either way the hang swings, about its tie.
    private static let swing: Double = 3

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let u = LaunchLayout.unit(in: size) * zoom
            ZStack {
                Image("janur-hang")
                    .resizable()
                    .frame(width: Self.hang.width * u, height: Self.hang.height * u)
                    .scaleEffect(x: side, y: 1)
                    .rotationEffect(.degrees(swung ? Self.swing : -Self.swing), anchor: .top)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: swingPeriod / 2).repeatForever(autoreverses: true),
                        value: swung
                    )
                    // On top of the idle swing, its own animation: a loose
                    // spring, retargeted on every motion update, so the hang
                    // overshoots and wobbles like a weight on a string. The
                    // sides' springs differ with their periods, so a tilt
                    // sets them wobbling out of step.
                    .rotationEffect(.degrees(tilt.lean), anchor: .top)
                    .animation(.spring(response: swingPeriod / 3.5, dampingFraction: 0.35), value: tilt.lean)
                    .position(
                        x: x(Self.hangCentreIn, size),
                        y: y(Self.hangTopUp, size) + Self.hang.height * u / 2
                    )
                Image("janur-pole")
                    .resizable()
                    .frame(width: Self.pole.width * u, height: Self.pole.height * u)
                    .scaleEffect(x: side, y: 1)
                    .position(
                        x: x(Self.poleCentreIn, size),
                        y: y(Self.poleTopUp, size) + Self.pole.height * u / 2
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if !reduceMotion { swung = true } }
    }

    /// From the mockup to where the camera sees it: scaled about the middle
    /// of the bottom edge, the anchor the gate and the rest of the landing
    /// screen zoom about.
    private func x(_ inFromEdge: CGFloat, _ size: CGSize) -> CGFloat {
        let u = LaunchLayout.unit(in: size)
        let atRest = side < 0 ? inFromEdge * u : size.width - inFromEdge * u
        return size.width / 2 + (atRest - size.width / 2) * zoom
    }

    private func y(_ upFromBottom: CGFloat, _ size: CGSize) -> CGFloat {
        size.height - upFromBottom * LaunchLayout.unit(in: size) * zoom
    }
}

/// The penjor's easter egg: where the real ground is, as an angle on screen
/// for the sampian to hang towards. One per landing screen, shared by both
/// penjor — Core Motion wants one manager per app, not one per view.
///
/// Gravity and the user's own acceleration only (`deviceMotion`), which need
/// no permission prompt — unlike motion activity, which would.
@Observable
final class HangTilt {
    /// Degrees, clockwise on screen: where the hang points, 0 straight down.
    private(set) var lean: Double = 0

    @ObservationIgnored private let motion = CMMotionManager()

    /// How far it may lean either way. It was 50 (short of swinging through
    /// its own pole), with the full tilt and a 40° jolt — too much: the
    /// hangs flailed at every move of the hand.
    private static let most: Double = 20
    /// How much of the device's tilt the hang follows. Not all of it: held in
    /// the hand, a phone is always a little off level.
    private static let follow: Double = 0.4
    /// Degrees of swing for a sideways jolt of 1 g.
    private static let jolt: Double = 12

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            update(data)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }

    private func update(_ data: CMDeviceMotion) {
        // Core Motion speaks in the device's portrait axes (x right, y to the
        // top). The app is landscape-only, so it is held one of two ways;
        // into screen axes (x right, y down) for whichever this is.
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let topRight = scene?.effectiveGeometry.interfaceOrientation == .landscapeLeft
        let g = data.gravity
        let a = data.userAcceleration
        let (x, y, push) = topRight ? (g.y, g.x, a.y) : (-g.y, -g.x, -a.y)
        // Lying flat, gravity has nothing in the screen's plane and its angle
        // there is noise: the lean fades out as the phone goes flat.
        let upright = min(1, hypot(x, y) * 1.5)
        let down = atan2(-x, y) * 180 / .pi * upright * Self.follow
        // Pushed to the right, the tie moves right and the hang lags behind
        // it — swinging clockwise.
        let lean = down + push * Self.jolt
        self.lean = max(-Self.most, min(Self.most, lean))
    }
}

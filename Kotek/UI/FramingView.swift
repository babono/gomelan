//
//  FramingView.swift
//  Kotek
//
//  Setup step 2/4 (PRD §3.2, §8). Mount the phone above the gangsa and settle
//  the stand until the bilah sit roughly under the guide. Rough is the point:
//  step 3/4 is where the masks are fitted exactly.
//
//  Two things this screen must get right, and used to get wrong:
//
//   1. FULL-BLEED CAMERA. The preview used to sit in a VStack under the top bar,
//      inset, clipped and dimmed 35% — you could not really see the instrument
//      you were being asked to aim at. Worse, aspect-fill in a letterboxed view
//      crops the scene DIFFERENTLY from the full-bleed aligning screen, so what
//      you lined up here shifted the moment you continued. Both screens are now
//      the same full-bleed space, so the framing carries over exactly.
//
//   2. ONE AREA, not ten boxes. A row of individual key outlines is impossible
//      to line a real instrument up against — and pointless, since the next step
//      exists to place them. All this step has to establish is "every bilah is
//      inside here", which is also what makes the prediction on 3/4 tractable:
//      it turns the search region from the whole room into the instrument.
//

import SwiftUI
import QuartzCore

struct FramingView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController

    /// Whether the camera is actually delivering pictures yet. Starting a
    /// capture session takes a moment, and until it does this screen is a black
    /// rectangle with a dashed box on it — which looks like something is broken
    /// rather than like something is loading.
    @State private var cameraReady = false
    /// Set the instant Continue is tapped, so the tap has a visible effect while
    /// the next screen brings its own preview up.
    @State private var handingOver = false

    private var busyMessage: String? {
        if handingOver { return "Finding your keys…" }
        return cameraReady ? nil : "Starting the camera…"
    }

    var body: some View {
        ZStack {
            CameraPreview(camera: camera)
                .ignoresSafeArea()

            FramingRegion(region: app.framedRegion)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TopBar(title: "Frame the gangsa",
                       backTitle: "Back",
                       onBack: { app.screen = .choosingKeyCount },
                       trailingText: "2 / 4",
                       tint: Theme.cream, accent: Theme.copper,
                       compact: true)
                    .background(
                        LinearGradient(colors: [.black.opacity(0.55), .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea(edges: .top)
                    )

                Spacer()

                bottomBar
            }
        }
        .background(Theme.ink)
        .busy(busyMessage)
        .onAppear { camera.start() }
        .task {
            // Wait for a real frame rather than for `status == .running`: the
            // session reports running before the first picture comes out.
            let deadline = CACurrentMediaTime() + 6
            while !cameraReady, !Task.isCancelled {
                if camera.frameBuffer.nearest(to: CACurrentMediaTime()) != nil
                    || CACurrentMediaTime() > deadline {
                    //R Give up after a while and let the screen through. A
                    //R camera that never delivers — no permission, no hardware —
                    //R must not leave the player stuck behind a scrim with the
                    //R Back button underneath it.
                    cameraReady = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    /// One line, tight: every point this strip gives back is a point the framing
    /// window gets.
    private var bottomBar: some View {
        HStack(spacing: 16) {
            SectionLabel("Fit every key inside the frame — fill it as much as you can",
                         color: Theme.copper)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 12)

            PillButton(title: "Continue", style: .filled, tint: Theme.copper, compact: true) {
                //R Cover the gap the tap opens: the next screen builds a fresh
                //R preview layer, which is black until it gets its first frame.
                //R The spinner starts here and the aligning screen picks it up
                //R with the same wording, so it reads as one wait, not two.
                //R
                //R The navigation is deferred by a frame ON PURPOSE. Changing
                //R screen in the same turn tears this view down before SwiftUI
                //R ever draws the overlay, which is why the tap looked like it
                //R did nothing at all.
                handingOver = true
                Task {
                    try? await Task.sleep(for: .milliseconds(50))
                    app.framingConfirmed()
                }
            }
            .disabled(!cameraReady)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        //R Sits low, in the home-indicator strip rather than above it, so the
        //R caption clears the dashed edge instead of straddling it.
        .padding(.bottom, 2)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.65)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// The area every bilah has to sit inside. Everything outside it is dimmed, so
/// the frame reads as a window rather than as a decoration — and so it is
/// obvious when a bar is hanging out of it.
private struct FramingRegion: View {
    let region: NormalizedRect

    var body: some View {
        GeometryReader { geo in
            let rect = region.rect(in: geo.size)
            let shape = RoundedRectangle(cornerRadius: 14)

            ZStack {
                Color.black.opacity(0.42)
                    .reverseMask {
                        shape.frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }

                shape
                    .strokeBorder(Theme.copper.opacity(0.9),
                                  style: StrokeStyle(lineWidth: 2, dash: [10, 7]))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }
}

private extension View {
    /// Punch a hole in this view in the shape of `mask`.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            ZStack {
                Rectangle()
                mask().blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}

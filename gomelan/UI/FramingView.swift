//
//  FramingView.swift
//  gomelan
//
//  Setup step 2/3 (PRD §3.2, §8). Mount the phone above the gangsa and settle
//  the stand until the bilah sit roughly under the guide. Rough is the point:
//  step 3/3 is where the masks are fitted exactly.
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
//      inside here", which is also what makes the prediction on 3/3 tractable:
//      it turns the search region from the whole room into the instrument.
//

import SwiftUI

struct FramingView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            FramingRegion(region: app.framedRegion)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TopBar(title: "Frame the instrument",
                       backTitle: "Back",
                       onBack: { app.screen = .choosingKeyCount },
                       trailingText: "2 / 3",
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
        .onAppear { camera.start() }
    }

    /// One line, tight: every point this strip gives back is a point the framing
    /// window gets.
    private var bottomBar: some View {
        HStack(spacing: 16) {
            SectionLabel("Fit every bilah inside the frame — fill it as much as you can",
                         color: Theme.copper)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 12)

            PillButton(title: "Continue", style: .filled, tint: Theme.copper, compact: true) {
                app.framingConfirmed()
            }
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

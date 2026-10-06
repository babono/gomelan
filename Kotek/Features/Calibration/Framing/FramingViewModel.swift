//
//  FramingViewModel.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import CoreGraphics
import Foundation
import Observation
import QuartzCore

@Observable
@MainActor
final class FramingViewModel {
    private let app: AppState
    let camera: CameraController

    /// Whether the camera is actually delivering pictures yet.
    var cameraReady = false
    /// Set the instant Continue is tapped, so the tap has a visible effect while
    /// the next screen brings its own preview up.
    var handingOver = false

    var bleed: CGRect = .zero
    var headerBottom: CGFloat = 0
    var captionTop: CGFloat = 0

    /// Clearance between the dashed edge and the chrome it sits between.
    private static let chromeGap: CGFloat = 8

    init(app: AppState, camera: CameraController) {
        self.app = app
        self.camera = camera
    }

    /// The window every bilah has to sit inside, spanning the whole width and
    /// everything between the header and the caption.
    var region: NormalizedRect {
        guard bleed.height > 0, headerBottom > 0, captionTop > headerBottom else {
            return app.framedRegion
        }
        let top = (headerBottom - bleed.minY + Self.chromeGap) / bleed.height
        let bottom = (captionTop - bleed.minY - Self.chromeGap) / bleed.height
        return NormalizedRect(x: 0, y: top, w: 1, h: bottom - top)
    }

    var busyMessage: String? {
        if handingOver { return "Finding your keys…" }
        return cameraReady ? nil : "Starting the camera…"
    }

    func setup() {
        camera.start()
    }

    func waitForCamera() async {
        let deadline = CACurrentMediaTime() + 6
        while !cameraReady, !Task.isCancelled {
            if camera.frameBuffer.nearest(to: CACurrentMediaTime()) != nil
                || CACurrentMediaTime() > deadline {
                cameraReady = true
                break
            }
            try? await Task.sleep(for: .milliseconds(60))
        }
    }

    func updateFramedRegion() {
        app.framedRegion = region
    }

    func confirmFraming() {
        handingOver = true
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            app.framingConfirmed()
        }
    }
}

//
//  CameraPreview.swift
//  Kotek
//
//  UIViewRepresentable hosting the shared AVCaptureVideoPreviewLayer (PRD §6.1).
//  Fills the view with an aspect-fill preview; the overlay is drawn above it.
//
//  It HOSTS the layer rather than owning one. Each screen used to declare its
//  own preview layer via `layerClass` and assign `.session` to it, and assigning
//  a session adds a connection — which, on an already-running session, makes
//  AVFoundation renegotiate. That was measured at 9007ms on the main thread
//  going from the demo screen into a run: the entire delay between "I'm ready"
//  and the count-in appearing. `CameraController` now owns exactly one layer,
//  attached once during preload while the session is still stopped, and a
//  screen change just re-parents it. `addSublayer` removes it from its previous
//  superlayer, so the layer follows whichever preview is on screen.
//
//  The orientation applied to the preview is forwarded to the video-data-output
//  connection, so the frames handed to the vision classifier are rotated
//  identically to what's on screen.
//

import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    /// The controller, not just its session: the shared layer lives on it.
    let camera: CameraController
    /// Whether to keep this controller's detection buffers rotated to match the
    /// preview. Only the screens that classify crops need it.
    var forwardsRotation: Bool = false

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(previewLayer: camera.previewLayer)
        view.controller = forwardsRotation ? camera : nil
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.controller = forwardsRotation ? camera : nil
        // Re-adopt the layer if another screen has taken it since. Cheap when
        // it is already here, and the difference between a live preview and a
        // black rectangle when it is not.
        uiView.adoptLayerIfNeeded()
        uiView.updateOrientation()
    }

    final class PreviewView: UIView {
        weak var controller: CameraController?
        let previewLayer: AVCaptureVideoPreviewLayer

        init(previewLayer: AVCaptureVideoPreviewLayer) {
            self.previewLayer = previewLayer
            super.init(frame: .zero)
            layer.addSublayer(previewLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used from a nib") }

        func adoptLayerIfNeeded() {
            guard previewLayer.superlayer !== layer else { return }
            layer.addSublayer(previewLayer)
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // The layer is shared and long-lived, so a resize or a re-parent
            // would otherwise animate implicitly — the preview visibly sliding
            // or stretching into place on every screen change.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
            updateOrientation()
        }

        func updateOrientation() {
            guard let connection = previewLayer.connection else { return }
            if let windowScene = window?.windowScene {
                let orientation = windowScene.interfaceOrientation
                let targetAngle: Double = switch orientation {
                case .portrait: 90
                case .portraitUpsideDown: 270
                case .landscapeLeft: 180
                case .landscapeRight: 0
                @unknown default: 90
                }

                if connection.isVideoRotationAngleSupported(targetAngle) {
                    connection.videoRotationAngle = targetAngle
                }

                // Keep the classified frames in the same space as the preview.
                controller?.setVideoRotationAngle(targetAngle)
            }
        }
    }
}

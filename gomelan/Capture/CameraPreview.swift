//
//  CameraPreview.swift
//  gomelan
//
//  UIViewRepresentable hosting the AVCaptureVideoPreviewLayer (PRD §6.1).
//  Fills the view with an aspect-fill preview; the overlay is drawn above it.
//
//  When a `controller` is supplied, the same orientation applied to the preview
//  is forwarded to the video-data-output connection, so the frames handed to the
//  vision classifier are rotated identically to what's on screen.
//

import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// Optional: keep this controller's detection buffers rotated to match the
    /// preview. Only the detection screens need it.
    var controller: CameraController? = nil

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.controller = controller
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.controller = controller
        uiView.updateOrientation()
    }

    final class PreviewView: UIView {
        weak var controller: CameraController?

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateOrientation()
        }

        func updateOrientation() {
            guard let connection = videoPreviewLayer.connection else { return }
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
                } else if connection.isVideoOrientationSupported {
                    switch orientation {
                    case .portrait: connection.videoOrientation = .portrait
                    case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
                    case .landscapeLeft: connection.videoOrientation = .landscapeLeft
                    case .landscapeRight: connection.videoOrientation = .landscapeRight
                    @unknown default: connection.videoOrientation = .portrait
                    }
                }

                // Rotate the detection frames the same way as the preview.
                controller?.setVideoRotationAngle(targetAngle)
            }
        }
    }
}

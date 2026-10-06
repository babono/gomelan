//
//  DetectionTestView.swift
//  Kotek
//
//  Dev screen for the REAL practice-mode detector. Unlike MalletTestView (which
//  shows raw per-frame vision probabilities), this runs the exact pipeline that
//  play/practice uses — vision self-trigger (rising edge) + audio timing snap —
//  and reports which key it decides was hit. If a strike registers wrong here,
//  it registers wrong in practice, so this is the screen to debug the combined
//  detection on.
//

import QuartzCore
import SwiftUI
import Vision

struct DetectionTestView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController
    let audio: AudioEngineController

    @State private var viewModel: DetectionTestViewModel

    init(camera: CameraController, audio: AudioEngineController) {
        self.camera = camera
        self.audio = audio
        _viewModel = State(wrappedValue: DetectionTestViewModel(camera: camera, audio: audio))
    }

    var body: some View {
        @Bindable var app = app
        return ZStack {
            CameraPreview(camera: camera, forwardsRotation: true)
                .ignoresSafeArea()

            DetectionKeyOverlay(
                keys: app.profile.keys,
                scores: viewModel.scores,
                visionThreshold: app.visionThreshold,
                lastHitKey: viewModel.lastHit?.key
            )

            if app.markerVision {
                DetectionMarkerOverlay(
                    isFrontPOV: app.markerPOV == MarkerPOV.front.rawValue,
                    bandEdges: viewModel.bandEdges,
                    roiTop: app.markerROITop,
                    markerFrame: viewModel.markerFrame
                )
            }

            DetectionBannerView(hit: viewModel.lastHit)

            chrome
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { viewModel.updateOverlaySize(proxy.size) }
                    .onChange(of: proxy.size) { _, new in viewModel.updateOverlaySize(new) }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            viewModel.start(app: app)
        }
        .onDisappear {
            viewModel.stop(app: app)
        }
        .task { await viewModel.runDetection(app: app) }
        .task { await viewModel.pollDictionary() }
        .onChange(of: markerSettingsSignature) { _, _ in
            viewModel.applyMarkerSettings(app: app)
        }
        .onChange(of: app.visionThreshold) { _, new in
            viewModel.handleVisionThresholdChanged(new)
        }
        .onChange(of: app.requireMarker) { _, _ in
            viewModel.handleRequireMarkerChanged(app: app)
        }
        .onChange(of: app.markerVision) { _, _ in
            viewModel.handleMarkerVisionChanged(app: app)
        }
        .onChange(of: app.markerExposureBias) { _, _ in
            viewModel.configureMarkerCamera(app: app)
        }
    }

    // MARK: - Chrome

    private var chrome: some View {
        @Bindable var app = app
        return VStack {
            HStack(spacing: 16) {
                SecondaryButton(title: "Back", systemImage: "chevron.left") {
                    app.closeDetectionTest()
                }
                Spacer()
                HStack(spacing: 8) {
                    Circle()
                        .fill(audio.isRunning ? Theme.hit : Theme.miss)
                        .frame(width: 10, height: 10)
                    Text("vision + audio")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.black.opacity(0.6), in: Capsule())
            }
            .padding(.horizontal, 24).padding(.top, 24)

            HStack(alignment: .top) {
                if viewModel.showDictionary {
                    DetectionDictionaryPanel(app: app, viewModel: viewModel)
                } else {
                    dictionaryToggle
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)

            Spacer()

            DetectionLogPanel(log: viewModel.log)
        }
    }

    private var dictionaryToggle: some View {
        Button {
            viewModel.showDictionary = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "waveform.and.magnifyingglass")
                Text("dict")
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.black.opacity(0.6), in: Capsule())
        }
        .buttonStyle(.kajar)
    }

    /// Every value `applyMarkerSettings` pushes into the fusion actor, in one
    /// Equatable bundle so a single `.onChange` can watch the lot.
    private var markerSettingsSignature: [Double] {
        [app.markerBrightness, Double(app.markerColour), app.markerSaturationFloor,
         app.markerSaturation, app.markerMinSpeed, app.markerTipExtension,
         app.markerROITop, Double(app.markerPOV), app.markerBandLeft,
         app.markerBandRight, app.markerBandSkew, app.markerBandFlip ? 1 : 0]
    }
}

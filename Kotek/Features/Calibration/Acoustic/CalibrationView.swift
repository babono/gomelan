//
//  CalibrationView.swift
//  Kotek
//
//  Baseline · learn this gamelan's voice.
//
//  Gomelan no longer calibrates each bilah's pitch. It only needs to learn what
//  a real strike on THIS gangsa SOUNDS like — one generic spectral template —
//  so that during play a genuine strike can be told apart from a scream, a clap
//  or a hovering mallet. The learner just listens: strike any key a few times,
//  soft and hard, and a confidence ring fills as clean strikes accumulate.
//
//  Backed by AudioEngineController's baseline API:
//    startBaselineCapture() → onOnsetDebug (per strike) → finishBaselineCapture()
//

import SwiftUI

struct CalibrationView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController
    let audio: AudioEngineController

    var body: some View {
        CalibrationContentView(app: app, camera: camera, audio: audio)
    }
}

private struct CalibrationContentView: View {
    let app: AppState
    let camera: CameraController
    let audio: AudioEngineController
    @State private var viewModel: CalibrationViewModel

    init(app: AppState, camera: CameraController, audio: AudioEngineController) {
        self.app = app
        self.camera = camera
        self.audio = audio
        _viewModel = State(wrappedValue: CalibrationViewModel(app: app, camera: camera, audio: audio))
    }

    var body: some View {
        ZStack {
            CameraPreview(camera: camera)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.22).ignoresSafeArea())

            KeyOutlinesOverlay(keys: app.profile.keys)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TopBar(
                    title: "Learn this gangsa's voice",
                    backTitle: "Cancel",
                    onBack: { viewModel.cancel() },
                    trailingText: "4 / 4",
                    tint: Theme.cream,
                    accent: Theme.copper,
                    compact: true
                )
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.5), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: [.top, .horizontal])
                )

                Spacer()

                CalibrationBottomBar(
                    learned: viewModel.learned,
                    lastAccepted: viewModel.lastAccepted,
                    micLevel: viewModel.micLevel,
                    micLevelTime: viewModel.micLevelTime,
                    strikeCount: viewModel.strikeCount,
                    strikesNeeded: viewModel.strikesNeeded,
                    confidence: viewModel.confidence,
                    committing: viewModel.committing,
                    onReset: { viewModel.reset() },
                    onCommit: { viewModel.commit() }
                )
            }
        }
        .background(Theme.ink)
        .busy(viewModel.busyMessage)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.teardown() }
    }
}

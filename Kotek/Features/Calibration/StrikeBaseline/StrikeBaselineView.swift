//
//  StrikeBaselineView.swift
//  Kotek
//
//  A single generic "strike baseline" capture, replacing the per-key pitch
//  calibration. Vision decides *which* key was hit, so the app no longer needs a
//  fingerprint per key — only what *a* gangsa strike sounds like, enough to tell
//  a real strike from a scream, clap, or a mallet hovering over the keys. The
//  user strikes any keys a few times; the averaged spectrum becomes the optional
//  strike gate used during play.
//

import FactoryKit
import SwiftUI

struct StrikeBaselineView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        StrikeBaselineContentView(app: app)
    }
}

private struct StrikeBaselineContentView: View {
    let app: AppState
    @State private var viewModel: StrikeBaselineViewModel

    init(
        app: AppState,
        camera: CameraController = Container.shared.cameraService(),
        audio: AudioEngineController = Container.shared.audioService()
    ) {
        self.app = app
        _viewModel = State(wrappedValue: StrikeBaselineViewModel(app: app, camera: camera, audio: audio))
    }

    var body: some View {
        ZStack {
            CameraPreview(camera: viewModel.camera)
                .ignoresSafeArea()

            KeyOutlinesOverlay(
                keys: app.profile.keys,
                strokeColor: .white.opacity(0.3),
                lineWidth: Theme.keyOutlineWidth
            )
            .ignoresSafeArea()

            VStack {
                header
                Spacer()
                panel
            }
            .padding(24)
        }
        .busy(viewModel.busyMessage)
        .onAppear { viewModel.setup() }
        .onDisappear { viewModel.teardown() }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            AppButton(title: "Skip", systemImage: "chevron.right", size: .compact) {
                viewModel.finish(enableGate: false)
            }
            Spacer()
            Text("Strike baseline")
                .font(.sans(17))
                .foregroundStyle(.white)
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .background(.black.opacity(0.55), in: Capsule())
            Spacer()
            Spacer().frame(width: 90)
        }
    }

    private var panel: some View {
        VStack(spacing: 16) {
            Text(viewModel.statusText)
                .font(.sans(16))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            // `silent`, not a tick — the ONE control in the app with no tick
            // on it. This button starts the microphone learning what a strike
            // on this gangsa sounds like, and a kajar rung by the press itself
            // would still be decaying inside the first window that capture
            // records. The app would learn that a button is a strike.
            AppButton(
                title: viewModel.recordTitle,
                systemImage: viewModel.capturing ? "checkmark" : "waveform.badge.plus",
                prominence: .primary,
                size: .large,
                tint: viewModel.capturing ? .red : nil,
                fullWidth: true,
                silent: true
            ) { viewModel.toggleCapture() }
                .frame(maxWidth: 420)

            if let count = viewModel.strikeCount, count > 0, !viewModel.capturing {
                AppButton(
                    title: "Continue",
                    systemImage: "checkmark.circle.fill",
                    prominence: .primary,
                    size: .large,
                    fullWidth: true
                ) {
                    viewModel.finish(enableGate: true)
                }
                .frame(width: 280)
            }
        }
        .padding(20)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
        .padding(.bottom, 16)
    }
}

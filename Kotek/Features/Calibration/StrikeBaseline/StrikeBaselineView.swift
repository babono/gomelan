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

import SwiftUI

struct StrikeBaselineView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController
    let audio: AudioEngineController

    var body: some View {
        StrikeBaselineContentView(app: app, camera: camera, audio: audio)
    }
}

private struct StrikeBaselineContentView: View {
    let app: AppState
    let camera: CameraController
    let audio: AudioEngineController
    @State private var viewModel: StrikeBaselineViewModel

    init(app: AppState, camera: CameraController, audio: AudioEngineController) {
        self.app = app
        self.camera = camera
        self.audio = audio
        _viewModel = State(wrappedValue: StrikeBaselineViewModel(app: app, camera: camera, audio: audio))
    }

    var body: some View {
        ZStack {
            CameraPreview(camera: camera)
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
            SecondaryButton(title: "Skip", systemImage: "chevron.right") {
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

            Button(action: { viewModel.toggleCapture() }) {
                HStack(spacing: 10) {
                    Image(systemName: viewModel.capturing ? "checkmark" : "waveform.badge.plus")
                        .font(.title2)
                    Text(viewModel.recordTitle)
                }
                .font(.sans(17))
                .foregroundStyle(viewModel.capturing ? .white : .black)
                .padding(.vertical, 14)
                .padding(.horizontal, 24)
                .frame(maxWidth: 420)
                .background(viewModel.capturing ? Color.red : Theme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            // `.plain`, not `.kajar` — the ONE control in the app with no tick
            // on it. This button starts the microphone learning what a strike
            // on this gangsa sounds like, and a kajar rung by the press itself
            // would still be decaying inside the first window that capture
            // records. The app would learn that a button is a strike.
            .buttonStyle(.plain)

            if let count = viewModel.strikeCount, count > 0, !viewModel.capturing {
                PrimaryButton(title: "Continue", systemImage: "checkmark.circle.fill") {
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

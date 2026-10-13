//
//  NoteCaptureView.swift
//  Kotek
//
//  Dev screen: record one struck key at a time and save it as a fixed-length
//  clip, labelled by key index, under Documents/NoteClips (see NoteClipCapture).
//  Audio only, so no camera: the instrument is drawn as numbered bars.
//

import SwiftUI

struct NoteCaptureView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NoteCaptureContentView(app: app)
    }
}

private struct NoteCaptureContentView: View {
    let app: AppState
    @State private var viewModel: NoteCaptureViewModel

    init(app: AppState) {
        self.app = app
        _viewModel = State(wrappedValue: NoteCaptureViewModel(app: app))
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                title: "Capture note clips",
                backTitle: "Back",
                onBack: { app.closeNoteCapture() },
                trailingText: "\(viewModel.keysWithClips.count) / \(app.profile.keys.count)",
                tint: Theme.cream,
                accent: Theme.copper,
                compact: true
            )

            HStack(spacing: 0) {
                NoteKeyBarsView(
                    keyIndices: app.profile.keys.map(\.index),
                    selected: viewModel.keyIndex,
                    recorded: viewModel.keysWithClips,
                    enabled: !viewModel.isRecording,
                    onSelect: { viewModel.select($0) }
                )
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                NoteCapturePanel(viewModel: viewModel)
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.teardown() }
    }
}

//
//  NoteCaptureView.swift
//  Kotek
//
//  Dev screen: record one struck key at a time and save it as a fixed-length
//  clip, labelled by key index, under Documents/NoteClips (see NoteClipCapture).
//  Audio only, so no camera: the instrument is drawn as numbered bars.
//
//  Also step 2 of adding a gangsa (`noteCaptureIsSetup`), where it wears the
//  redesign's setup header and Kipli asks for each bilah in turn.
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
            if app.noteCaptureIsSetup {
                // Step 2 of adding a gangsa: the redesign's header, and Kipli
                // asking for the bilah by name.
                SetupHeader(
                    step: 2,
                    onLeading: app.backToKeyCount,
                    trailingTitle: viewModel.keysWithClips.isEmpty ? "Skip" : "Done",
                    onTrailing: app.closeNoteCapture
                )
                .padding(.horizontal, 24)
            } else {
                TopBar(
                    title: "Capture note clips",
                    backTitle: "Back",
                    onBack: app.closeNoteCapture,
                    trailingText: "\(viewModel.keysWithClips.count) / \(app.profile.keys.count)",
                    accent: Theme.copper,
                    compact: true
                )
            }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    if app.noteCaptureIsSetup {
                        Text("Hit bilah \(NoteCaptureViewModel.number(for: viewModel.keyIndex))")
                            .font(.serif(26))
                            .foregroundStyle(Theme.heading)
                    }
                    NoteKeyBarsView(
                        keyIndices: app.profile.keys.map(\.index),
                        selected: viewModel.keyIndex,
                        recorded: viewModel.keysWithClips,
                        enabled: !viewModel.isRecording,
                        onSelect: { viewModel.select($0) },
                        listening: viewModel.isRecording
                    )
                    .frame(maxHeight: .infinity)
                    KipliGuide(
                        message: "\(viewModel.keysWithClips.count) of \(app.profile.keys.count) recorded. Tap one to record it again."
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, Theme.footerBottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                NoteCapturePanel(viewModel: viewModel)
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.teardown() }
    }
}

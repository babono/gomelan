//
//  NoteCapturePanel.swift
//  Kotek
//
//  Right-hand panel: everything about the selected key. Its graph is live while
//  recording, the saved clip afterwards (with a moving line while it plays), or
//  a plain "not recorded" note.
//

import SwiftUI

struct NoteCapturePanel: View {
    let viewModel: NoteCaptureViewModel
    @State private var confirmingDelete = false

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                SectionLabel("Key \(NoteCaptureViewModel.number(for: viewModel.keyIndex))", color: Theme.copper)
                Spacer()
                AppIconButton(
                    systemImage: "trash",
                    label: "Delete recording",
                    prominence: .destructive
                ) {
                    confirmingDelete = true
                }
                .disabled(!canPlay)
            }
            .frame(height: 24)

            graph
                .frame(height: 110)
                .frame(maxWidth: .infinity)

            Text(viewModel.message ?? viewModel.statusText)
                .font(.sans(13, weight: .medium))
                .foregroundStyle(viewModel.phase == .strike ? Theme.cream : Theme.inkStone)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            AppButton(
                "Record",
                systemImage: "record.circle",
                prominence: .primary,
                fullWidth: true,
                silent: true,
                action: { viewModel.record() }
            )
            .disabled(viewModel.isRecording)

            HStack(spacing: 8) {
                AppButton(
                    viewModel.isPlaying ? "Stop" : "Play",
                    systemImage: viewModel.isPlaying ? "stop.fill" : "play.fill",
                    fullWidth: true,
                    silent: true,
                    action: { viewModel.togglePlayback() }
                )
                .disabled(!canPlay)

                AppIconButton(systemImage: "arrow.right", label: "Next key") {
                    viewModel.next()
                }
                .disabled(!canNext)
            }
        }
        .padding(14)
        .frame(width: 232)
        .frame(maxHeight: .infinity)
        .background(Theme.inkRaised.opacity(0.9))
        .confirmationDialog(
            "Delete the recording for key \(NoteCaptureViewModel.number(for: viewModel.keyIndex))?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { viewModel.deleteRecording() }
        }
    }

    private var canNext: Bool {
        viewModel.hasNext && !viewModel.isRecording
    }

    private var canPlay: Bool {
        viewModel.keysWithClips.contains(viewModel.keyIndex) && !viewModel.isRecording
    }

    @ViewBuilder private var graph: some View {
        if viewModel.isRecording {
            NoteWaveformView(levels: viewModel.liveLevels)
        } else if viewModel.waveform.isEmpty {
            Text("Key \(NoteCaptureViewModel.number(for: viewModel.keyIndex)) not recorded")
                .font(.sans(15, weight: .medium))
                .foregroundStyle(Theme.cream.opacity(0.7))
        } else {
            TimelineView(.animation(paused: !viewModel.isPlaying)) { _ in
                NoteWaveformView(
                    levels: viewModel.waveform,
                    progress: viewModel.isPlaying ? viewModel.playbackProgress : nil
                )
            }
        }
    }
}

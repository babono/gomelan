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
                Button {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.symbol(16, weight: .semibold))
                        .foregroundStyle(Theme.miss)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.kajar)
                .disabled(!canPlay)
                .opacity(canPlay ? 1 : 0.35)
                .accessibilityLabel("Delete recording")
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

            PillButton(
                title: "Record",
                systemImage: "record.circle",
                style: .filled,
                tint: Theme.copper,
                fullWidth: true,
                compact: true,
                silent: true,
                action: { viewModel.record() }
            )
            .disabled(viewModel.isRecording)
            .opacity(viewModel.isRecording ? 0.5 : 1)

            HStack(spacing: 8) {
                PillButton(
                    title: viewModel.isPlaying ? "Stop" : "Play",
                    systemImage: viewModel.isPlaying ? "stop.fill" : "play.fill",
                    style: .outlined,
                    tint: Theme.copper,
                    fullWidth: true,
                    compact: true,
                    silent: true,
                    action: { viewModel.togglePlayback() }
                )
                .disabled(!canPlay)
                .opacity(canPlay ? 1 : 0.5)

                // Arrow only: PillButton has no icon-only form and this is its
                // single use. Same outlined-glass look so it reads as a sibling.
                Button {
                    viewModel.next()
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.symbol(14, weight: .semibold))
                        .foregroundStyle(Theme.cream)
                        .frame(width: 44, height: 38)
                        .background(Theme.cream.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.radius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.copper, lineWidth: 1))
                        .frame(minHeight: 44)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
                }
                .buttonStyle(.kajar)
                .disabled(!canNext)
                .opacity(canNext ? 1 : 0.5)
                .accessibilityLabel("Next key")
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

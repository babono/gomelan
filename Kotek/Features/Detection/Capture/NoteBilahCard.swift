//
//  NoteBilahCard.swift
//  Kotek
//
//  One recorded bilah: tap its tile and this opens beside it, playing. Hear it
//  again, or redo it. Delete is Settings' alone: setup only ever goes forward,
//  and a redo already replaces the take.
//

import SwiftUI

struct NoteBilahCard: View {
    let viewModel: NoteCaptureViewModel
    let key: Int
    let deletes: Bool
    @State private var confirmingDelete = false

    static func width(deletes: Bool) -> CGFloat {
        deletes ? 290 : 240
    }

    private var number: Int {
        NoteCaptureViewModel.number(for: key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bilah \(number)")
                    .font(.sans(17, weight: .semibold))
                    .foregroundStyle(Theme.heading)
                Spacer()
                if viewModel.isPlaying {
                    Text("Playing…")
                        .font(.sans(13))
                        .foregroundStyle(Theme.description)
                }
            }

            TimelineView(.animation(paused: !viewModel.isPlaying)) { _ in
                NoteWaveformView(
                    levels: viewModel.waveform,
                    progress: viewModel.isPlaying ? viewModel.playbackProgress : nil,
                    tint: Theme.primary
                )
            }
            .frame(height: 28)

            HStack(spacing: 8) {
                AppButton(
                    title: viewModel.isPlaying ? "Stop" : "Listen",
                    systemImage: viewModel.isPlaying ? "stop.fill" : "play.fill",
                    size: .compact,
                    fullWidth: true,
                    silent: true,
                    action: { viewModel.togglePlayback() }
                )
                AppButton(
                    title: "Redo",
                    systemImage: "arrow.clockwise",
                    size: .compact,
                    fullWidth: true,
                    silent: true,
                    action: { viewModel.redo(key) }
                )
                if deletes {
                    AppIconButton(systemImage: "trash", label: "Delete recording", size: .compact, tint: Theme.miss) {
                        confirmingDelete = true
                    }
                }
            }
        }
        .padding(14)
        .frame(width: Self.width(deletes: deletes))
        .background(Theme.deep, in: RoundedRectangle(cornerRadius: 16))
        .compositingGroup()
        .shadow(color: Theme.ireng.opacity(0.25), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { viewModel.closeCard() }
        .confirmationDialog(
            "Delete the recording for key \(number)?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { viewModel.deleteRecording() }
        }
    }
}

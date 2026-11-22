//
//  NoteCaptureView.swift
//  Kotek
//
//  Record one sound per bilah and save it as a fixed-length clip, labelled by
//  key index, under Documents/NoteClips (see NoteClipCapture). Audio only: the
//  instrument is drawn as numbered tiles.
//
//  Hands-free. Start listening once, then just play the real bilah, one hit
//  each; the tiles fill in and Kipli keeps up. Once every tile has a clip it
//  is the review, "Have a listen": tap a tile to hear it (`NoteBilahCard`).
//
//  Step 2 of adding a gangsa (`noteCaptureIsSetup`) wears the setup header;
//  from Settings it wears a top bar, and the card can delete a recording.
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
                SetupHeader(
                    step: 2,
                    onLeading: app.backToKeyCount,
                    trailingTitle: viewModel.isReview ? nil : "Skip",
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

            VStack(spacing: 12) {
                Text(viewModel.isReview ? "Have a listen" : "Record your gangsa")
                    .font(.serif(30))
                    .foregroundStyle(Theme.heading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                NoteKeyBarsView(
                    keyIndices: app.profile.keys.map(\.index),
                    current: viewModel.currentKey,
                    recorded: viewModel.keysWithClips,
                    quiet: viewModel.quietKeys,
                    inspected: viewModel.inspected,
                    phase: viewModel.phase,
                    onSelect: { viewModel.inspect($0) }
                )
                // Centred in the space left: on an iPad's taller screen, top-aligned tiles sat high.
                .frame(maxHeight: .infinity)

                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, Theme.footerBottom)
        }
        .overlayPreferenceValue(InspectedTileBounds.self) { anchor in
            if let anchor, let key = viewModel.inspected {
                GeometryReader { geo in
                    card(for: key, beside: geo[anchor], in: geo.size)
                }
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.teardown() }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            KipliGuide(message: viewModel.kipliLine, mood: viewModel.kipliMood)
            Spacer(minLength: 0)
            if let quiet = viewModel.quietKeys.first {
                AppButton(
                    title: "Redo \(NoteCaptureViewModel.number(for: quiet))",
                    systemImage: "arrow.clockwise",
                    size: .large,
                    silent: true,
                    action: { viewModel.redo(quiet) }
                )
                .fixedSize()
            }
            if viewModel.isListening || viewModel.isReview {
                AppButton(
                    title: app.noteCaptureIsSetup ? "Next" : "Done",
                    prominence: .primary,
                    size: .large,
                    action: app.closeNoteCapture
                )
                .disabled(viewModel.isListening)
                .fixedSize()
            } else {
                // Silent: a tick now would be the first thing it hears.
                AppButton(
                    title: "Start listening",
                    systemImage: "mic.fill",
                    prominence: .primary,
                    size: .large,
                    silent: true,
                    action: { viewModel.startListening() }
                )
                .fixedSize()
            }
        }
    }

    /// Beside the tile, on whichever side it fits; tapping anywhere else closes it.
    private func card(for key: Int, beside tile: CGRect, in size: CGSize) -> some View {
        let width = NoteBilahCard.width(deletes: !app.noteCaptureIsSetup)
        let fitsRight = tile.maxX + 10 + width <= size.width
        return ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { viewModel.closeCard() }
                .accessibilityHidden(true)
            NoteBilahCard(viewModel: viewModel, key: key, deletes: !app.noteCaptureIsSetup)
                .position(
                    x: fitsRight ? tile.maxX + 10 + width / 2 : tile.minX - 10 - width / 2,
                    y: tile.midY
                )
        }
    }
}

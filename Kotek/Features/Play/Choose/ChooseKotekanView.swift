//
//  ChooseKotekanView.swift
//  Kotek
//
//  Pick the interlocking figure to learn. Tapping the focused card goes straight
//  to the count-in — this is the last decision before playing.
//

import FactoryKit
import SwiftUI

struct ChooseKotekanView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ChooseKotekanContentView(app: app)
    }
}

private struct ChooseKotekanContentView: View {
    let app: AppState
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel: ChooseKotekanViewModel

    init(app: AppState, cue: CuePlayer = Container.shared.cueService()) {
        self.app = app
        _viewModel = State(wrappedValue: ChooseKotekanViewModel(app: app, cue: cue))
    }

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            TopBar(
                title: "Choose your kotekan",
                onBack: { app.openChooseInstrument() },
                settingsAction: { app.openSettings() },
                infoAction: { app.openGuide(.kotekan) }
            )
            ControllerStatusChip()

            carousel
                .frame(maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .horizontal)

            ChooseKotekanFooter(
                muted: $vm.muted,
                current: vm.current,
                playable: vm.playable,
                onStart: { vm.start($0) },
                onCreate: { vm.create() },
                onEdit: { vm.edit($0) },
                onDelete: { vm.pendingDelete = $0 },
                onCoop: { vm.coop($0) }
            )
        }
        .confirm(
            Binding(get: { vm.pendingDelete != nil }, set: { if !$0 { vm.pendingDelete = nil } }),
            title: "Delete this kotekan?",
            message: "\(vm.pendingDelete?.name ?? "It") will be removed from this account on every device. Its records on your gangsa stay.",
            confirmTitle: "Delete"
        ) {
            if let k = vm.pendingDelete { vm.delete(k) }
        }
        .overlay(alignment: .top) {
            if let error = vm.deleteError {
                Text(error)
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Theme.cream)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.miss.opacity(0.9), in: Capsule())
                    .padding(.top, 60)
                    .onTapGesture { vm.deleteError = nil }
            }
        }
        .onAppear { vm.onAppear() }
        .onDisappear { vm.onDisappear() }
        .onChange(of: vm.wrap(vm.focusedSlot)) { _, _ in vm.onSlotChanged() }
        .onChange(of: scenePhase) { _, phase in vm.handleScenePhase(phase) }
        .onChange(of: vm.muted) { _, isMuted in vm.handleMutedChanged(isMuted) }
    }

    // MARK: - The carousel

    private var carousel: some View {
        GeometryReader { geo in
            let first = Int((viewModel.position - 2).rounded(.down))
            let last = Int((viewModel.position + 2).rounded(.up))

            ZStack {
                ForEach(first ... last, id: \.self) { slot in
                    let offset = Double(slot) - viewModel.position
                    Group {
                        if let k = viewModel.kotekan(atSlot: slot) {
                            KotekanCardView(
                                kotekan: k,
                                isPlaying: slot == viewModel.focusedSlot,
                                offset: offset,
                                canPlay: viewModel.isPlayable(k),
                                engine: viewModel.engine,
                                bestRecord: viewModel.bestRecord(k)
                            )
                        } else {
                            CreateKotekanCardView(offset: offset)
                        }
                    }
                    .position(
                        x: geo.size.width / 2 + CGFloat(offset) * ChooseKotekanViewModel.step,
                        y: geo.size.height / 2
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(swipe(width: geo.size.width))
        }
        .clipped()
    }

    private func swipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                viewModel.onDragChanged(translationWidth: value.translation.width)
            }
            .onEnded { value in
                viewModel.onDragEnded(
                    translationWidth: value.translation.width,
                    predictedEndTranslationWidth: value.predictedEndTranslation.width,
                    startLocationX: value.startLocation.x,
                    width: width
                )
            }
    }
}

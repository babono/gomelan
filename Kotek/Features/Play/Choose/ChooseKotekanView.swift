//
//  ChooseKotekanView.swift
//  Kotek
//
//  Pick the interlocking figure to learn. Tapping a card only brings it to the
//  middle and plays it; Start, bottom right, is the one way on to the count-in.
//  A tap on the focused card used to start the session, and a tap meant to
//  hear a figure again kept throwing the player into one.
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

        // The page ignores the keyboard: the search field is up top beside
        // Create, so the keyboard has nothing to push out of the way, and
        // letting the page avoid it squeezed the carousel into a sliver.
        VStack(spacing: 0) {
            TopBar(
                title: "Choose your kotekan",
                onBack: { app.openChooseInstrument() },
                settingsAction: { app.openSettings() },
                showsSensor: true,
                edgeInset: 0
            )
            SearchAndCreateBar(
                query: $vm.query,
                prompt: "Search kotekan",
                createTitle: "Create kotek",
                onCreate: { vm.create() }
            )

            Group {
                if vm.kotekans.isEmpty {
                    noMatches
                } else {
                    carousel
                }
            }
            // Inside the safe area: run to the screen edge, the side cards
            // slid under the Dynamic Island.
            .frame(maxHeight: .infinity)

            ChooseKotekanFooter(
                muted: $vm.muted,
                current: vm.current,
                playable: vm.playable,
                onStart: { vm.start($0) },
                onEdit: { vm.edit($0) },
                onDelete: { vm.pendingDelete = $0 },
                onCoop: { vm.coop($0) }
            )
        }
        .ignoresSafeArea(.keyboard)
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
        // The figure, not the slot: a search can change what sits in the
        // focused slot without the slot moving.
        .onChange(of: vm.current?.id) { _, _ in vm.onSlotChanged() }
        .onChange(of: scenePhase) { _, phase in vm.handleScenePhase(phase) }
        .onChange(of: vm.muted) { _, isMuted in vm.handleMutedChanged(isMuted) }
    }

    private var noMatches: some View {
        VStack(spacing: 8) {
            Text("No kotekan called “\(viewModel.query)”")
                .font(.serif(26))
                .foregroundStyle(Theme.cream)
            Text("Try another name, or create it yourself.")
                .font(.sans(14))
                .foregroundStyle(Theme.stone)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - The carousel

    private var carousel: some View {
        GeometryReader { geo in
            // The side cards are sized to end on the rail's edge, so at rest
            // nothing is cut; `step` follows from that size.
            let side = CarouselFit.sideScale(width: geo.size.width, card: KotekanCardView.cardWidth)
            let gap = CarouselFit.gap(width: geo.size.width, card: KotekanCardView.cardWidth)
            let step = KotekanCardView.cardWidth / 2 + gap + side * KotekanCardView.cardWidth / 2
            let first = Int((viewModel.position - 2).rounded(.down))
            let last = Int((viewModel.position + 2).rounded(.up))

            ZStack {
                ForEach(first ... last, id: \.self) { slot in
                    let offset = Double(slot) - viewModel.position
                    if let k = viewModel.kotekan(atSlot: slot) {
                        KotekanCardView(
                            kotekan: k,
                            isPlaying: slot == viewModel.focusedSlot,
                            offset: offset,
                            canPlay: viewModel.isPlayable(k),
                            engine: viewModel.engine,
                            // Nothing is scored without the sensor, so a record would be a number nobody can beat.
                            bestRecord: app.controllerConnected ? viewModel.bestRecord(k) : nil,
                            sideScale: side
                        )
                        .position(
                            x: geo.size.width / 2 + CGFloat(offset) * step,
                            y: geo.size.height / 2
                        )
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(swipe(width: geo.size.width, step: step))
        }
        .clipped()
    }

    private func swipe(width: CGFloat, step: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                viewModel.onDragChanged(translationWidth: value.translation.width, step: step)
            }
            .onEnded { value in
                viewModel.onDragEnded(
                    translationWidth: value.translation.width,
                    predictedEndTranslationWidth: value.predictedEndTranslation.width,
                    startLocationX: value.startLocation.x,
                    width: width,
                    step: step
                )
            }
    }
}

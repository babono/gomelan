//
//  ChooseKotekanView.swift
//  Kotek
//
//  Pick the interlocking figure to learn. A swipe or a tap on a side card
//  brings it to the middle and plays it; a tap on the centred card starts it
//  — alone, or into the coop setup when the corner menu says Co-op — and a
//  long press there lifts it for Edit / Delete.
//
//  Start, bottom right, was the one way on for a while, because a tap on the
//  focused card used to start the session and a tap meant to hear a figure
//  again kept throwing the player into one. A side card still only centres
//  (that is how you hear it), so the tap that starts is always the second one.
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

        // The field is at the bottom now, so the page has to make room for the
        // keyboard (it used to ignore it, with the field up top).
        VStack(spacing: 0) {
            TopBar(
                title: "Choose your kotekan",
                onBack: { app.openChooseInstrument() },
                settingsAction: { app.openSettings() },
                showsMenu: true,
                accessory: AnyView(modeMenu),
                edgeInset: 0
            )

            Group {
                if vm.kotekans.isEmpty {
                    noMatches
                } else {
                    carousel
                }
            }
            .frame(maxHeight: .infinity)

            SearchAndCreateBar(
                query: $vm.query,
                prompt: "Search",
                createTitle: "Create kotek",
                onCreate: { vm.create() }
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
        // The figure, not the slot: a search can change what sits in the
        // focused slot without the slot moving.
        .onChange(of: vm.current?.id) { _, _ in vm.onSlotChanged() }
        .onChange(of: scenePhase) { _, phase in vm.handleScenePhase(phase) }
        .onChange(of: vm.muted) { _, isMuted in vm.handleMutedChanged(isMuted) }
    }

    private var modeMenu: some View {
        @Bindable var app = app
        return AppMenuPicker(
            options: PlayMode.allCases,
            selection: $app.playMode,
            title: \.title,
            label: "Mode",
            systemImage: app.playMode == .solo ? "person.fill" : "person.2.fill",
            size: .regular
        )
        .fixedSize()
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

            let height = min(KotekanCardView.maxHeight, geo.size.height - 16)

            let first = Int((viewModel.position - 3).rounded(.down))
            let last = Int((viewModel.position + 3).rounded(.up))

            ZStack {
                ForEach(first ... last, id: \.self) { slot in
                    let offset = Double(slot) - viewModel.position
                    if let k = viewModel.kotekan(atSlot: slot) {
                        card(k, focused: slot == viewModel.focusedSlot, offset: offset, side: side, height: height)
                            .position(
                                x: geo.size.width / 2 + CGFloat(offset.sign == .minus ? -1 : 1)
                                    * (min(abs(CGFloat(offset)), 1) * step
                                        + max(abs(CGFloat(offset)) - 1, 0)
                                        * (side * KotekanCardView.cardWidth + gap)),
                                y: geo.size.height / 2
                            )
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(swipe(width: geo.size.width, step: step))
        }
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

    /// Only the centred card takes touches, for its mute and its long press;
    /// the rest stay out of the drag's way, as every card did before.
    private func card(_ k: Kotekan, focused: Bool, offset: Double, side: CGFloat, height: CGFloat) -> some View {
        @Bindable var vm = viewModel
        return KotekanCardView(
            kotekan: k,
            isPlaying: focused,
            canPlay: vm.isPlayable(k),
            engine: vm.engine,
            // Nothing is scored without the sensor, so a record would be a number nobody can beat.
            bestRecord: app.controllerConnected ? vm.bestRecord(k) : nil,
            muted: $vm.muted,
            offset: offset,
            sideScale: side,
            height: height
        )
        .contextMenu {
            // The built-ins are the app's: shown, but greyed with the reason,
            // so a long press never looks like it did nothing.
            let builtin = k.source == .builtin
            Section {
                Button("Edit", systemImage: "pencil") { vm.edit(k) }
                    .disabled(builtin)
                Button("Delete", systemImage: "trash", role: .destructive) { vm.pendingDelete = k }
                    .disabled(builtin)
            } header: {
                if builtin { Text("Built-in kotekan can't be edited or deleted") }
            }
        }
        .allowsHitTesting(focused)
    }
}

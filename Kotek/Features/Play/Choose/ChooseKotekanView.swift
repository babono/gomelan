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

        VStack(spacing: 0) {
            TopBar(
                title: "Choose your kotekan",
                subtitle: "On \(app.profile.name)",
                onBack: { app.openChooseInstrument() },
                settingsAction: { app.openSettings() },
                infoAction: { app.openGuide(.kotekan) },
                infoLabel: "How kotekan works",
                infoSubtitle: "Polos, sangsih and how they fit",
                showsMenu: true,
                accessory: AnyView(HStack(spacing: 14) { SensorChip()
                    modeMenu
                }),
                edgeInset: 0
            )

            // Kipli in the gap between the header and the rail, his bubble
            // opening to his right. In the bottom row the filter pills covered
            // it; among the header's controls it dropped onto the subtitle.
            KipliGuide(message: "Swipe to hear each kotekan. Tap one to play it.", style: .quiet)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Above the rail, which is drawn after him.
                .zIndex(1)

            Group {
                if vm.kotekans.isEmpty {
                    noMatches
                } else {
                    carousel
                }
            }
            .frame(maxHeight: .infinity)

            filterBar
        }
        .confirm(
            Binding(get: { vm.pendingDelete != nil }, set: { if !$0 { vm.pendingDelete = nil } }),
            title: "Delete this kotekan?",
            message: "\(vm.pendingDelete?.name ?? "It") will be removed from this account on every device. Its records on your gangsa stay.",
            confirmTitle: "Delete",
            kipli: .sad
        ) {
            if let k = vm.pendingDelete { vm.delete(k) }
        }
        .sheet(item: $vm.shareURL) { ShareSheet(items: [$0]) }
        .overlay {
            if vm.askSignInToShare {
                LinkApplePrompt(
                    title: "Sign in to share",
                    message: "A shared kotekan is a link to your account. Link an Apple ID and anyone with the link can add a copy to their gangsa.",
                    origin: .chooseKotekan
                ) {
                    vm.askSignInToShare = false
                }
            }
        }
        .overlay(alignment: .top) {
            if let error = vm.deleteError {
                Text(error)
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Theme.onButtonFill)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.destructive, in: Capsule())
                    .padding(.top, 60)
                    .onTapGesture { vm.deleteError = nil }
            }
        }
        // Over everything, top bar and pills included, so the whole screen dims.
        .overlayPreferenceValue(CardAnchorKey.self) { anchors in
            if let k = vm.menuFor, let anchor = anchors[k.id] {
                CardMenuOverlay(anchor: anchor, items: menuItems(for: k)) { size in
                    KotekanCardView(
                        kotekan: k,
                        isPlaying: true,
                        canPlay: vm.isPlayable(k),
                        engine: vm.engine,
                        bestRecord: app.controllerConnected ? vm.bestRecord(k) : nil,
                        muted: $vm.muted,
                        offset: 0,
                        sideScale: 1,
                        height: size.height
                    )
                } onDismiss: {
                    vm.menuFor = nil
                }
            }
        }
        .onAppear { vm.onAppear() }
        .onDisappear { vm.onDisappear() }
        // The figure, not the slot: a filter can change what sits in the
        // focused slot without the slot moving.
        .onChange(of: vm.current?.id) { _, _ in vm.onSlotChanged() }
        .onChange(of: app.selectedKotekan?.id) { _, id in vm.land(on: id) }
        .onChange(of: scenePhase) { _, phase in vm.handleScenePhase(phase) }
        .onChange(of: app.visibleGuide != nil) { _, open in vm.handleGuideChanged(open: open) }
        .onChange(of: vm.muted) { _, isMuted in vm.handleMutedChanged(isMuted) }
    }

    /// What a held card offers. Learn again: a learned pattern's tap goes
    /// straight into free play, so this is the way back to the steps.
    ///
    /// R Edit and Delete were greyed out on the built-ins with a reason
    /// R header; a menu half of which can't be used read as broken. They are
    /// R only there now on the player's own figures.
    private func menuItems(for k: Kotekan) -> [CardMenuItem] {
        let vm = viewModel
        var items: [CardMenuItem] = []
        if vm.isPlayable(k) {
            items.append(LearnProgress.isDone(k.id)
                ? CardMenuItem(title: "Learn again", systemImage: "arrow.clockwise") { vm.learn(k) }
                : CardMenuItem(title: "Learn step by step", systemImage: "graduationcap") { vm.learn(k) })
        }
        items.append(CardMenuItem(title: "Hear polos only", systemImage: "speaker.wave.2") { vm.hear(.polos) })
        items.append(CardMenuItem(title: "Hear sangsih only", systemImage: "speaker.wave.2") { vm.hear(.sangsih) })
        // Built-ins are on every phone already.
        if k.source != .builtin {
            items.append(CardMenuItem(title: "Share", systemImage: "square.and.arrow.up") { vm.share(k) })
            items.append(CardMenuItem(title: "Edit", systemImage: "pencil") { vm.edit(k) })
            items
                .append(CardMenuItem(title: "Delete", systemImage: "trash", destructive: true) { vm.pendingDelete = k })
        }
        return items
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

    /// The pills bottom left, + bottom right, flush to the safe-area edge
    /// where the top bar's buttons and the rail's outer cards end.
    private var filterBar: some View {
        @Bindable var vm = viewModel
        return HStack(spacing: 10) {
            AppSwitcher(
                options: KotekanFilter.allCases,
                selection: vm.filter,
                title: \.title,
                size: .regular,
                style: .pills
            ) { vm.filter = $0 }
            Spacer(minLength: 0)
            AppIconButton(systemImage: "plus", label: "Create kotek") { vm.create() }
        }
        .padding(.bottom, Theme.footerBottom)
    }

    private var noMatches: some View {
        VStack(spacing: 8) {
            Text(noMatchesTitle)
                .font(.serif(26))
                .foregroundStyle(Theme.heading)
            Text(noMatchesDetail)
                .font(.sans(14))
                .foregroundStyle(Theme.stone)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchesTitle: LocalizedStringKey {
        switch viewModel.filter {
        case .all: "No kotekan yet"
        case .new: "You've learned them all"
        case .learned: "Nothing learned yet"
        case .mine: "No kotek of your own yet"
        }
    }

    private var noMatchesDetail: LocalizedStringKey {
        switch viewModel.filter {
        case .all, .mine: "Tap + to make one."
        case .new: "Find them under Learned."
        case .learned: "Finish Learn on a pattern and it shows up here."
        }
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
                viewModel.onDragChanged(
                    translationWidth: value.translation.width,
                    startLocationX: value.startLocation.x,
                    width: width,
                    step: step
                )
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
        .cardAnchor(k.id)
        .cardMenuAccessibility(menuItems(for: k))
        .allowsHitTesting(focused)
    }
}

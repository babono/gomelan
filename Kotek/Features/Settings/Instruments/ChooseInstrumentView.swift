//
//  ChooseInstrumentView.swift
//  Kotek
//
//  Choose which saved gamelan to play. Profiles persist key alignments and
//  strike baselines across app launches and builds.
//
//  Laid out like Choose your kotekan: a centred carousel of the same card
//  size, + under it. The card in the middle is the selected one —
//  swiping or tapping a card brings it there; a tap on the centred card goes
//  on, and a long press lifts it for Edit (its section in Settings) / Delete.
//
//  A tap on any card used to go straight to the kotekan picker, which made a
//  mis-tap on the wrong gangsa a trip back, so Next took over. Next is gone
//  again, but a side card still only centres, so going on is always a second,
//  deliberate tap. The cards were once 240pt tall photo cards, which with the
//  search row and a footer ran off a landscape phone; they are the kotekan
//  card's 210 now the footer is gone, and still capped by the rail's height.
//
//  The search field that sat beside + is gone, as it is on the kotekan
//  picker: a player has a few gangsa, and swiping finds one sooner than
//  typing its name.
//

import SwiftUI

struct ChooseInstrumentView: View {
    @Environment(AppState.self) private var app
    /// The card in the middle of the carousel — the selected gangsa.
    @State private var centred: String?
    /// The gangsa waiting on the delete confirmation.
    @State private var pendingDelete: InstrumentProfile?
    /// The gangsa being renamed, and the name being typed for it.
    @State private var renaming: InstrumentProfile?
    @State private var newName = ""
    /// The gangsa whose menu is open, from a long press on its card.
    @State private var menuFor: InstrumentProfile?
    /// Set as the hold opens the menu, so the release is not also taken as
    /// the card's tap. Cleared by that tap or by closing the menu.
    @State private var heldOpen = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                title: "Choose your gangsa",
                subtitle: app.savedProfiles.isEmpty ? nil : "Which one are you playing today?",
                onBack: { app.screen = .welcome },
                settingsAction: { app.openSettings() },
                edgeInset: 0
            )

            if app.savedProfiles.isEmpty {
                EmptyInstrumentsView(onAdd: { app.addNewInstrument() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                rail
                    .frame(maxHeight: .infinity)
                // Bottom right, flush to the safe-area edge, as on the kotekan picker.
                HStack {
                    Spacer()
                    AppIconButton(systemImage: "plus", label: "Add gangsa") { app.addNewInstrument() }
                }
                .padding(.bottom, Theme.footerBottom)
            }
        }
        .confirm(
            Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            title: "Delete this gangsa?",
            message: LocalizedStringKey(GangsaDeletion.message(pendingDelete?.name)),
            confirmTitle: "Delete"
        ) {
            guard let p = pendingDelete else { return }
            app.deleteInstrument(p.id)
            // The app moves to the next gangsa; centre its card. An empty
            // list shows the set-up screen by itself.
            withAnimation(.snappy(duration: 0.32)) { centred = app.profile.id }
        }
        .overlayPreferenceValue(CardAnchorKey.self) { anchors in
            if let profile = menuFor, let anchor = anchors[profile.id] {
                CardMenuOverlay(anchor: anchor, items: menuItems(for: profile)) { size in
                    InstrumentCardView(profile: profile, isCurrent: true, height: size.height, onSelect: {})
                } onDismiss: {
                    menuFor = nil
                    heldOpen = false
                }
            }
        }
        .alert("Rename gangsa", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Gangsa name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { rename() }
        }
        .onAppear {
            app.showGuideIfFirstRun(.app)

            guard let first = app.savedProfiles.first,
                  !app.savedProfiles.contains(where: { $0.id == app.profile.id })
            else { return }
            app.activateInstrument(first)
        }
        .onChange(of: centred) { _, id in
            if let p = app.savedProfiles.first(where: { $0.id == id }) { app.activateInstrument(p) }
        }
    }

    private func card(_ profile: InstrumentProfile, height: CGFloat) -> some View {
        InstrumentCardView(
            profile: profile,
            isCurrent: app.profile.id == profile.id,
            height: height,
            onSelect: {
                if heldOpen {
                    heldOpen = false
                    return
                }
                if centred == profile.id {
                    app.selectInstrument(profile)
                } else {
                    withAnimation(.snappy(duration: 0.32)) { centred = profile.id }
                }
            }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                heldOpen = true
                menuFor = profile
            }
        )
        .cardAnchor(profile.id)
        .cardMenuAccessibility(menuItems(for: profile))
    }

    /// What a gangsa needs doing, each straight to its screen; "Edit" used to
    /// drop the player into all of Settings.
    private func menuItems(for profile: InstrumentProfile) -> [CardMenuItem] {
        [
            CardMenuItem(title: "Rename", systemImage: "pencil") {
                newName = profile.name
                renaming = profile
            },
            CardMenuItem(title: "Re-record sounds", systemImage: "waveform") {
                app.activateInstrument(profile)
                app.openNoteCapture(returnTo: .chooseInstrument)
            },
            CardMenuItem(title: "Set up sensors", systemImage: "dot.radiowaves.left.and.right") {
                app.activateInstrument(profile)
                app.openControllerSetup(returnTo: .chooseInstrument)
            },
            CardMenuItem(title: "Remove", systemImage: "trash", destructive: true) {
                pendingDelete = profile
            }
        ]
    }

    /// An empty name keeps the old one, as the Settings field does.
    private func rename() {
        guard var p = renaming else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != p.name else { return }
        p.name = trimmed
        if app.profile.id == p.id { app.profile = p }
        app.saveInstrument(p)
    }

    // MARK: - The rail

    private var rail: some View {
        GeometryReader { geo in
            // The side cards are sized to end on the rail's edge, as on the
            // kotekan picker. The scroll transition this replaces scaled by
            // how much of the card was on screen, so a neighbour's resting
            // size depended on the width and landed under the Dynamic Island.
            let side = CarouselFit.sideScale(width: geo.size.width, card: InstrumentCardView.width)
            let gap = CarouselFit.gap(width: geo.size.width, card: InstrumentCardView.width)
            let step = InstrumentCardView.width + gap
            // Read here, not in `visualEffect`: its closure is Sendable and
            // cannot reach a main-actor static.
            let cardWidth = InstrumentCardView.width

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: gap) {
                    ForEach(app.savedProfiles) { profile in
                        card(profile, height: min(InstrumentCardView.maxHeight, geo.size.height - 16))
                            // Shrink and dim off-centre, as the kotekan carousel does,
                            // pinned at the edge facing the middle so the gap to the
                            // selected card stays `gap` and the outer edge is what moves.
                            .visualEffect { card, proxy in
                                // Against the scroll view's own bounds: it runs under the safe
                                // area, so its midpoint is not the rail's.
                                let centre = proxy.bounds(of: .scrollView)?.midX ?? 0
                                let dx = proxy.frame(in: .scrollView).midX - centre
                                let t = min(abs(dx) / step, 1)

                                let slide = (1 - side) * cardWidth * max(abs(dx) / (2 * step) - 1, 0)
                                return card
                                    .scaleEffect(1 - (1 - side) * t, anchor: dx < 0 ? .trailing : .leading)
                                    .offset(x: dx < 0 ? slide : -slide)
                                    .opacity(1 - 0.55 * t)
                            }
                            .id(profile.id)
                    }
                }
                .scrollTargetLayout()
                .frame(maxHeight: .infinity)
            }
            .scrollClipDisabled()
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centred, anchor: .center)
            .safeAreaPadding(.horizontal, max(0, (geo.size.width - InstrumentCardView.width) / 2))
        }
        .onAppear { centred = app.profile.id }
    }
}

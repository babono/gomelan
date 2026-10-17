//
//  ChooseInstrumentView.swift
//  Kotek
//
//  Choose which saved gamelan to play. Profiles persist key alignments and
//  strike baselines across app launches and builds.
//
//  Laid out like Choose your kotekan: search and Add above a centred carousel
//  of the same card size, Next bottom right. The card in the middle is the
//  selected one — swiping or tapping a card brings it there; Next is the one
//  way on. A tap on a card used to go straight to the kotekan picker, which
//  made a mis-tap on the wrong gangsa a trip back. The cards were 240pt tall
//  photo cards, which with the search row and the footer ran off the bottom
//  of a landscape phone.
//

import SwiftUI

struct ChooseInstrumentView: View {
    @Environment(AppState.self) private var app
    @State private var query = ""
    /// The card in the middle of the carousel — the selected gangsa.
    @State private var centred: String?

    private var profiles: [InstrumentProfile] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return app.savedProfiles }
        return app.savedProfiles.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                title: "Choose your gangsa",
                onBack: { app.screen = .welcome },
                trailingText: app.savedProfiles.isEmpty
                    ? nil : "\(app.savedProfiles.count) saved",
                edgeInset: 0
            )

            if app.savedProfiles.isEmpty {
                EmptyInstrumentsView(onAdd: { app.addNewInstrument() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SearchAndCreateBar(
                    query: $query,
                    prompt: "Search gangsa",
                    createTitle: "Add gangsa",
                    onCreate: { app.addNewInstrument() }
                )
                Group {
                    if profiles.isEmpty { noMatches } else { rail }
                }
                .frame(maxHeight: .infinity)
                footer
            }
        }
        // As on the kotekan picker: the field is up top, so the keyboard has
        // nothing to push out of the way.
        .ignoresSafeArea(.keyboard)
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

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: gap) {
                    ForEach(profiles) { profile in
                        InstrumentCardView(
                            profile: profile,
                            isCurrent: app.profile.id == profile.id,
                            onSelect: { withAnimation(.snappy(duration: 0.32)) { centred = profile.id } }
                        )
                        // Shrink and dim off-centre, as the kotekan carousel does,
                        // pinned at the edge facing the middle so the gap to the
                        // selected card stays `gap` and the outer edge is what moves.
                        .visualEffect { card, proxy in
                            // Against the scroll view's own bounds: it runs under the safe
                            // area, so its midpoint is not the rail's.
                            let centre = proxy.bounds(of: .scrollView)?.midX ?? 0
                            let dx = proxy.frame(in: .scrollView).midX - centre
                            let t = min(abs(dx) / step, 1)
                            return card
                                .scaleEffect(1 - (1 - side) * t, anchor: dx < 0 ? .trailing : .leading)
                                .opacity(1 - 0.55 * t)
                        }
                        .id(profile.id)
                    }
                }
                .scrollTargetLayout()
                .frame(maxHeight: .infinity)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centred, anchor: .center)
            .safeAreaPadding(.horizontal, max(0, (geo.size.width - InstrumentCardView.width) / 2))
        }
        // A scroll view runs under the safe area; cut it at the rail's edge.
        .clipped()
        .onAppear { centred = app.profile.id }
        // A search that hides the centred card centres the first match.
        .onChange(of: query) { _, _ in
            if !profiles.contains(where: { $0.id == centred }) { centred = profiles.first?.id }
        }
    }

    private var noMatches: some View {
        VStack(spacing: 8) {
            Text("No gangsa called “\(query)”")
                .font(.serif(26))
                .foregroundStyle(Theme.cream)
            Text("Try another name, or add it.")
                .font(.sans(14))
                .foregroundStyle(Theme.stone)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Next goes with whichever card is selected — the one the app is already
    /// on until another is tapped.
    private var footer: some View {
        let selected = app.savedProfiles.contains { $0.id == app.profile.id }
        return HStack {
            Spacer()
            PillButton(title: "Next", style: .filled, compact: true) {
                app.selectInstrument(app.profile)
            }
            .disabled(!selected)
            .opacity(selected ? 1 : 0.4)
        }
        .padding(.bottom, 10)
    }
}

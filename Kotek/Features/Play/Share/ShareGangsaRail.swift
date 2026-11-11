//
//  ShareGangsaRail.swift
//  Kotek
//
//  The gangsa to add a shared kotekan to, as Choose your gangsa shows them:
//  the same `InstrumentCardView`, gold when chosen. It replaced a menu of
//  names — a player knows their gangsa by its photo before its name. A tap
//  only chooses here; Add is the footer's, and there is no long-press menu.
//
//  The chosen card sits at the rail's leading edge and the next one peeks in
//  from the right, shrunk, dimmed and fading out; the one before slides away
//  behind the leading edge. The picker's carousel — the chosen card in the
//  middle, peeks both ways — was tried first: beside the shared card that
//  rail was barely wider than one card, so `CarouselFit`'s gap came out
//  negative and the cards piled up, and with fixed peeks either side the
//  group sat off centre. One card wide with dots kept it centred but looked
//  bare. Here the caller centres the cards and lets the rail run on past
//  the chosen one to the screen's edge, so only the peek is outside the group.
//  To the screen's edge, not the safe area's: stopped at the safe area, the
//  peek was cut off in mid-air with paper beyond it.
//

import SwiftUI

struct ShareGangsaRail: View {
    let gangsa: [InstrumentProfile]
    @Binding var chosen: String?
    let cardHeight: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The cards beside the chosen one, and the space to it.
    private static let side: CGFloat = 0.8
    private static let gap: CGFloat = 14
    /// The soft fade at each end, and the room before the chosen card that
    /// keeps the leading one off its gold ring. The caller pulls the rail
    /// back by this much so the card itself stays where it centred it.
    static let fade: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            // Read here, not in `visualEffect`: its closure is Sendable and
            // cannot reach a main-actor static.
            let side = Self.side
            let inset = Self.fade
            let cardWidth = InstrumentCardView.width
            let step = cardWidth + Self.gap

            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Self.gap) {
                        ForEach(gangsa) { profile in
                            InstrumentCardView(
                                profile: profile,
                                isCurrent: chosen == profile.id,
                                height: cardHeight,
                                onSelect: { choose(profile.id) }
                            )
                            .accessibilityHint("Adds the kotekan to this gangsa")
                            // Room for the card's tactile base, which the
                            // scroll view would otherwise clip.
                            .padding(.bottom, 6)
                            .visualEffect { card, proxy in
                                // How far the card's leading edge is from where the
                                // chosen one rests, in the scroll view's own space.
                                // Not against `bounds(of: .scrollView)`: that comes
                                // back in the card's local space, so every card
                                // read further along than it was — the chosen one
                                // shrank and the peek was pulled in over it.
                                let dx = proxy.frame(in: .scrollView).minX - inset
                                let t = min(abs(dx) / step, 1)
                                // Pinned at the edge facing the chosen card, so the
                                // gap to it stays `gap`; the cards past the peek are
                                // drawn up behind it rather than left a card apart.
                                let slide = (1 - side) * cardWidth * max(dx / step - 1, 0)
                                return card
                                    .scaleEffect(1 - (1 - side) * t, anchor: dx < 0 ? .trailing : .leading)
                                    .offset(x: -slide)
                                    // The one before goes; the ones after dim.
                                    .opacity(dx < 0 ? 1 - t : 1 - 0.55 * t)
                            }
                            .id(profile.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .safeAreaPadding(.leading, inset)
                // So the last gangsa can come to the leading edge too.
                .contentMargins(.trailing, max(0, geo.size.width - inset - cardWidth), for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $chosen, anchor: .leading)
                // Opens on the gangsa already chosen, which need not be the first.
                .onAppear { reader.scrollTo(chosen, anchor: .leading) }
                // The same soft fade at both ends: the leading one for the card
                // going out, the trailing one at the screen's edge. One long
                // fade over the whole peek made it look washed out, and with
                // no fade on the leading side the outgoing card was sliced.
                .mask {
                    let edge = min(0.5, Self.fade / max(geo.size.width, 1))
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: edge),
                            .init(color: .black, location: 1 - edge),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
        }
    }

    private func choose(_ id: String) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.32)) { chosen = id }
    }
}

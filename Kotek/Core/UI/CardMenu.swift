//
//  CardMenu.swift
//  Kotek
//
//  The long-press menu on the pickers' cards: the screen dims, the card you
//  pressed grows where it stands, and its actions sit in a panel beside it.
//
//  R It was `.contextMenu`. In landscape iOS shrinks the lifted preview to
//  R fit its menu beside it, so the card you pressed came up SMALLER than the
//  R cards around it — and a custom preview a size up was shrunk the same
//  R way. Drawn here instead, the card keeps its place and grows.
//

import SwiftUI

struct CardMenuItem: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let systemImage: String
    var destructive = false
    let action: () -> Void
}

/// Where each card is on screen, by its id, for the menu to grow it in place.
struct CardAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Reports this card's frame under `id`, for `CardMenuOverlay`.
    func cardAnchor(_ id: String) -> some View {
        anchorPreference(key: CardAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

struct CardMenuOverlay<Card: View>: View {
    let anchor: Anchor<CGRect>
    let items: [CardMenuItem]
    /// The card again, at the size it has on screen, to draw grown.
    @ViewBuilder let card: (CGSize) -> Card
    let onDismiss: () -> Void

    /// How much the pressed card grows: a size up, so it reads as lifted.
    static var lift: CGFloat {
        1.08
    }

    /// Narrow enough to sit right of a centred card on a landscape phone;
    /// at 280 it spilled off the left edge instead.
    private let panelWidth: CGFloat = 240
    private let rowHeight: CGFloat = 48
    private let gap: CGFloat = 16

    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            let rect = geo[anchor]
            let grown = rect.width * (Self.lift - 1) / 2
            let panelHeight = rowHeight * CGFloat(items.count)
            // Right of the card if it fits, else left of it.
            let rightX = rect.maxX + grown + gap
            let leftX = rect.minX - grown - gap - panelWidth
            let overflow = rightX + panelWidth - (geo.size.width - 16)
            let goesLeft = overflow > 0 && leftX >= 16
            // Where neither side has room, the card steps left to make it,
            // rather than the panel covering it or running off the edge.
            let shift = goesLeft ? 0 : max(0, overflow)
            let x = goesLeft ? leftX : rightX - shift
            let y = min(max(rect.minY - rect.height * (Self.lift - 1) / 2, 16), geo.size.height - panelHeight - 16)

            ZStack(alignment: .topLeading) {
                Color.black.opacity(shown ? 0.6 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                card(rect.size)
                    // Opaque: the cards' own ground is translucent, and the
                    // card it was drawn from showed through, doubled.
                    .background(Theme.ground, in: RoundedRectangle(cornerRadius: 20))
                    .scaleEffect(shown ? Self.lift : 1)
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                    .position(x: rect.midX - (shown ? shift : 0), y: rect.midY)
                    .allowsHitTesting(false)

                panel
                    .frame(width: panelWidth)
                    .offset(x: x, y: y)
                    .opacity(shown ? 1 : 0)
                    .scaleEffect(shown ? 1 : 0.92, anchor: x > rect.midX ? .topLeading : .topTrailing)
            }
        }
        // The whole screen, edges too: inside the safe area a centred card
        // left too little room on its right for the panel.
        .ignoresSafeArea()
        .onAppear { withAnimation(.snappy(duration: 0.25)) { shown = true } }
        .sensoryFeedback(.impact(weight: .medium), trigger: shown) { _, now in now }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                if item.id != items.first?.id {
                    Rectangle().fill(Theme.cream.opacity(0.08)).frame(height: 1)
                }
                Button {
                    // Closed first, so an action that changes screen does not
                    // leave the menu animating out over the next one.
                    onDismiss()
                    item.action()
                } label: {
                    HStack {
                        Text(item.title)
                            .font(.sans(16))
                        Spacer(minLength: 12)
                        Image(systemName: item.systemImage)
                            .font(.symbol(16, weight: .medium))
                    }
                    .foregroundStyle(item.destructive ? Theme.miss : Theme.cream)
                    .padding(.horizontal, 18)
                    .frame(height: rowHeight - 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.appPlain)
            }
        }
        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.cream.opacity(0.1), lineWidth: 1))
    }
}

extension View {
    /// The card's menu actions for VoiceOver, which has no long press to find them.
    func cardMenuAccessibility(_ items: [CardMenuItem]) -> some View {
        accessibilityActions {
            ForEach(items) { item in
                Button(item.title, action: item.action)
            }
        }
    }
}

//
//  PolishView.swift
//  Kotek
//
//  "Where to polish": one pass of your half as a roll, faint, with the few
//  strokes that kept slipping marked on it — a gold pill where you hit, a
//  dashed one where it belongs, an arrow between — and numbered. Tap a number
//  and Kipli explains it, and the gold pill slides to its place.
//
//  Only your half, and only the spots. The graph this replaced drew both
//  halves and a landed share on every slot; reading it meant finding the two
//  strokes that mattered among thirty that did not.
//

import SwiftUI

struct PolishView: View {
    let result: SongResult
    let kotekan: Kotekan
    let half: KotekanHalf
    let spots: [PolishSpot]
    /// Every bilah on the gangsa in play, drawn when the roll has height for them.
    let keyCount: Int
    let onBack: () -> Void

    @State private var selected: Int?
    /// The selected spot's gold pill has slid to where it belongs.
    @State private var slid = false
    @State private var scroll = ScrollPosition(edge: .leading)
    /// How far the roll is scrolled, to tell which side of a spot has room
    /// for its card.
    @State private var offset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let labelWidth: CGFloat = 28
    private static let edgeWidth: CGFloat = 16
    private static let headerHeight: CGFloat = 22
    private static let minRow: CGFloat = 30

    private var voice: Color {
        half == .polos ? Theme.polosVoice : Theme.sangsihVoice
    }

    /// The figure's own bilah, and any struck instead of them, top to bottom
    /// highest first — as the gangsa is drawn on the waterfall. The whole
    /// gangsa when each of its bilah would still get `minRow` points: an iPad's
    /// taller roll has the room, a phone's does not and keeps to the figure.
    private func rows(height: CGFloat) -> [Int] {
        let struck = spots.compactMap { if case let .wrongBilah(k) = $0.kind { k } else { nil } }
        var low = min(kotekan.voicedKeyRange.lowerBound, struck.min() ?? .max)
        var high = max(kotekan.voicedKeyRange.upperBound, struck.max() ?? .min)
        if (height - Self.headerHeight - 8) / CGFloat(max(1, keyCount)) >= Self.minRow {
            low = 0
            high = max(high, keyCount - 1)
        }
        return Array((low ... high).reversed())
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                title: "Where to polish",
                subtitle: LocalizedStringKey(subtitle),
                onBack: onBack,
                // Two lines, as the mockup has him. Gone while a spot is open:
                // he has moved down beside its card to explain it.
                accessory: AnyView(
                    KipliGuide(message: kipliLine)
                        .frame(width: 290)
                        .opacity(selected == nil ? 1 : 0)
                )
            )
            roll
                .padding(.horizontal, 24)
                .padding(.bottom, Theme.footerBottom)
        }
    }

    /// "Ubitan Nyendok · Polos · all 4 cycles" — data, shown as typed.
    private var subtitle: String {
        let cycles = String(localized: "all \(result.cycles.count) cycles")
        return [kotekan.name, half.title, cycles].joined(separator: " · ")
    }

    private var kipliLine: LocalizedStringResource {
        "Here are \(spots.count) spots to look at. Tap one and I'll explain."
    }

    // MARK: - The roll

    /// R Slots are a fixed width and the roll scrolls sideways. Fitting the
    /// R whole cycle to the screen was tried first: fine for 16 slots, but a
    /// R 32-slot figure came out as slivers. The bilah numbers stay pinned
    /// R so a row can be read halfway along. They are a bar over the scroll,
    /// R as on the graph this replaced, so the system's soft edge blurs the
    /// R roll away under them; a column beside it cut every pill at a line.
    private var roll: some View {
        GeometryReader { geo in
            let grid = Grid(height: geo.size.height, slots: kotekan.slotsPerCycle, rows: rows(height: geo.size.height))
            let visible = geo.size.width - Self.labelWidth - Self.edgeWidth
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    beats(grid)
                    ForEach(result.strokes.indices, id: \.self) { i in
                        if !spots.contains(where: { $0.stroke == i }) {
                            let note = result.strokes[i]
                            pill(voice.opacity(0.22), grid)
                                .position(grid.point(key: note.keyIndex, slot: slot(of: note)))
                        }
                    }
                    ForEach(spots.indices, id: \.self) { i in
                        if selected != i { mark(i, grid) }
                    }
                    if let selected {
                        // Out past the content, under both bars: a scrim on each
                        // bar too dimmed twice where the roll slid beneath it.
                        scrim.padding(.horizontal, -geo.size.width)
                        mark(selected, grid)
                    }
                }
                .frame(width: grid.width, height: geo.size.height)
            }
            .safeAreaBar(edge: .leading, spacing: 0) {
                bilahNumbers(grid)
                    .frame(width: Self.labelWidth)
            }
            // Empty: only so the trailing edge blurs as the leading one does.
            .safeAreaBar(edge: .trailing, spacing: 0) {
                Color.clear
                    .frame(width: Self.edgeWidth)
            }
            .scrollEdgeEffectStyle(.soft, for: .horizontal)
            .scrollIndicators(.hidden)
            .scrollPosition($scroll)
            // From where the content starts, as `scrollTo(x:)` counts: at
            // rest `contentOffset` is minus the leading bar.
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x + $0.contentInsets.leading } action: {
                _, x in
                offset = x
            }
            .overlay(alignment: cardOnLeft(grid, visible: visible) ? .topLeading : .topTrailing) {
                if let selected {
                    explanation(selected, onLeft: cardOnLeft(grid, visible: visible))
                        .padding(16)
                        .transition(.opacity)
                }
            }
            .onChange(of: selected) {
                guard let selected else { return }
                bringIntoView(spots[selected], grid, visible: visible)
            }
        }
        .background(Theme.surface, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline))
        .clipShape(.rect(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.2), value: selected)
    }

    private var scrim: some View {
        Color.black.opacity(selected == nil ? 0 : 0.3)
            .contentShape(.rect)
            .allowsHitTesting(selected != nil)
            .onTapGesture { selected = nil }
            .accessibilityHidden(true)
    }

    /// Kipli and his card, side by side: the card is what he is saying, so he
    /// sits between it and the spot, facing in.
    private func explanation(_ i: Int, onLeft: Bool) -> some View {
        let face = KipliFace(height: 44, talking: !slid && !reduceMotion)
            .accessibilityHidden(true)
        let card = PolishCard(spot: spots[i], index: i, count: spots.count) { step($0) }
        return HStack(alignment: .top, spacing: 10) {
            if onLeft {
                card
                face
            } else {
                face
                card
            }
        }
    }

    /// Room for the card and Kipli to the spot's left, as the mockup has
    /// them; a spot too near the start to scroll that far gets them on its right.
    private static let explanationWidth: CGFloat = 270 + 10 + 44 * KipliFace.aspect + 32

    private func cardOnLeft(_ grid: Grid, visible: CGFloat) -> Bool {
        guard let selected else { return true }
        return grid.x(slot(of: spots[selected])) - offset >= Self.explanationWidth
    }

    /// Scrolls the spot to where its card leaves it showing: past the card on
    /// the left when there is room for that.
    private func bringIntoView(_ spot: PolishSpot, _ grid: Grid, visible: CGFloat) {
        let x = grid.x(slot(of: spot))
        let target = min(max(0, x - Self.explanationWidth - grid.column), max(0, grid.width - visible))
        withAnimation(.easeInOut(duration: 0.3)) { scroll.scrollTo(x: target) }
    }

    /// One spot: where it belongs (dashed), where it went (gold), the arrow
    /// between, and its number.
    @ViewBuilder
    private func mark(_ i: Int, _ grid: Grid) -> some View {
        let spot = spots[i]
        let slot = slot(of: spot)
        let home = grid.point(key: spot.keyIndex, slot: slot)
        // Kuning is ~1.8:1 on the roll's white, so gold alone vanished into it.
        // Black rings fixed that and shouted; `goldText` (Kuning deepened with
        // Ireng, the one gold that reads) keeps it all one hue, gold on gold.
        let dashed = pill(.clear, grid)
            .overlay(Capsule().strokeBorder(Theme.goldText, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
        let settled = selected == i && slid

        switch spot.kind {
        case .missed:
            dashed
                .padding(6)
                .background(Theme.gold.opacity(0.4), in: .capsule)
                .position(home)
        case .late, .early, .wrongBilah:
            let off: CGPoint = switch spot.kind {
            case .late: CGPoint(x: home.x + grid.column * 0.6, y: home.y)
            case .early: CGPoint(x: home.x - grid.column * 0.6, y: home.y)
            case let .wrongBilah(struck): grid.point(key: struck, slot: slot)
            case .missed: home
            }
            dashed.position(home)
            Image(systemName: arrow(spot))
                .font(.symbol(13, weight: .bold))
                .foregroundStyle(Theme.goldText)
                .position(spot.kind == .late || spot.kind == .early
                    ? CGPoint(x: (home.x + off.x) / 2, y: home.y - grid.tight * 0.45)
                    : CGPoint(x: home.x, y: (home.y + off.y) / 2))
                .opacity(settled ? 0 : 1)
            pill(Theme.gold, grid)
                .overlay(Capsule().strokeBorder(Theme.goldText, lineWidth: 1.5))
                .position(settled ? home : off)
        }

        Button {
            select(i)
        } label: {
            Text("\(i + 1)")
                .font(.sans(12, weight: .bold))
                .foregroundStyle(Theme.onButtonFill)
                .frame(width: 22, height: 22)
                .background(Theme.primary, in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.appPlain)
        .accessibilityLabel(Text(verbatim: spot.title))
        .position(x: home.x + grid.column * 0.55, y: home.y - grid.tight * 0.4)
    }

    /// From where it went towards where it belongs. Higher bilah are drawn
    /// higher, so a stroke struck above its bar points down.
    private func arrow(_ spot: PolishSpot) -> String {
        switch spot.kind {
        case .late: "arrow.left"
        case .early: "arrow.right"
        case let .wrongBilah(struck): struck > spot.keyIndex ? "arrow.down" : "arrow.up"
        case .missed: ""
        }
    }

    private func slot(of spot: PolishSpot) -> Int {
        slot(of: result.strokes[spot.stroke])
    }

    private func slot(of note: Note) -> Int {
        note.timeMs / max(1, kotekan.strokeMs)
    }

    private func pill(_ fill: Color, _ grid: Grid) -> some View {
        Capsule()
            .fill(fill)
            .frame(width: grid.pillWidth, height: grid.pillHeight)
    }

    /// The beat groups: a line before each and its number along the top.
    private func beats(_ grid: Grid) -> some View {
        ForEach(Array(stride(from: 0, to: kotekan.slotsPerCycle, by: 4)), id: \.self) { slot in
            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1)
                .padding(.top, Self.headerHeight)
                .offset(x: grid.x(slot) - grid.column / 2)
            Text("\(slot / 4 + 1)")
                .font(.sans(11, weight: .semibold))
                .foregroundStyle(Theme.stone)
                .position(x: grid.x(slot) - grid.column / 2 + 8, y: Self.headerHeight / 2 + 4)
                .accessibilityHidden(true)
        }
    }

    private func bilahNumbers(_ grid: Grid) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(grid.rows, id: \.self) { key in
                Text("\(key + 1)")
                    .font(.sans(11, weight: .semibold))
                    .foregroundStyle(Theme.stone)
                    .position(x: Self.labelWidth / 2 + 4, y: grid.y(key))
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    // MARK: - Selecting

    private func select(_ i: Int) {
        selected = i
        slid = false
        guard !reduceMotion else { return }
        // A beat to see where it went, then it slides home.
        withAnimation(.easeInOut(duration: 0.8).delay(0.5)) { slid = true }
    }

    private func step(_ by: Int) {
        guard let selected else { return }
        select(min(spots.count - 1, max(0, selected + by)))
    }

    /// Slot and bilah → points in the scrolling part of the roll.
    private struct Grid {
        let height: CGFloat
        let slots: Int
        let rows: [Int]

        /// One slot: room for a pill and the gap that keeps neighbours apart.
        let column: CGFloat = 44

        var width: CGFloat {
            column * CGFloat(max(1, slots)) + 16
        }

        var row: CGFloat {
            (height - PolishView.headerHeight - 8) / CGFloat(max(1, rows.count))
        }

        /// `row` capped, for what hangs off a pill (number, arrow): a tall roll
        /// with few bilah spread them a row apart from the pill they belong to.
        var tight: CGFloat {
            min(row, PolishView.minRow)
        }

        var pillWidth: CGFloat {
            column * 0.72
        }

        var pillHeight: CGFloat {
            min(row * 0.55, 20)
        }

        func x(_ slot: Int) -> CGFloat {
            8 + column * (CGFloat(slot) + 0.5)
        }

        func y(_ key: Int) -> CGFloat {
            PolishView.headerHeight + row * (CGFloat(rows.firstIndex(of: key) ?? 0) + 0.5)
        }

        func point(key: Int, slot: Int) -> CGPoint {
            CGPoint(x: x(slot), y: y(key))
        }
    }
}

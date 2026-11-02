//
//  ResultsPerformanceView.swift
//  Kotek
//
//  The results screen's left column: the piano roll with one half's landed
//  share drawn faintly behind it, a Polos / Sangsih switch to pick that half,
//  and a minimap of the whole figure under it.
//
//  The percentage used to be its own chart, with the roll a hold or a toggle
//  away. Two views of one session meant reading one, then the other; and the
//  hold to swap kept catching slow scrolls. One view, the curve behind the
//  blocks, has nothing to swap.
//

import SwiftUI

struct ResultsPerformanceView: View {
    /// Both halves' slots — rests included — folded over every pass.
    let slots: [PatternSlotScore]
    let keyCount: Int

    /// The half the curve and chips are for. Starts on the half the session
    /// finished on — the one the score is about.
    @State private var shown: KotekanHalf
    @State private var scrollSlot = -0.5
    @State private var visible = Self.maxVisible

    init(slots: [PatternSlotScore], keyCount: Int, half: KotekanHalf) {
        self.slots = slots
        self.keyCount = keyCount
        _shown = State(initialValue: half)
    }

    /// Five beat groups a screenful, at most — fewer when the column is too
    /// narrow to give each slot `PerformanceGraph.minColumn`, the width "100%" needs.
    private static let maxVisible = 20
    /// The roll's bilah numbers and % scale, which its slots do not get.
    private static let rollChrome: CGFloat = 28 + PerformanceGraph.scaleWidth

    private var columns: Int {
        (slots.map(\.slot).max() ?? -1) + 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Performance", color: Theme.stone)
                Spacer()
                AppSwitcher(
                    options: [KotekanHalf.polos, .sangsih],
                    selection: shown,
                    title: \.title,
                    tint: { $0 == .polos ? Theme.polosVoice : Theme.sangsihVoice }
                ) { shown = $0 }
                    .fixedSize()
            }

            PerformanceGraph(
                slots: slots, keyCount: keyCount, shown: shown,
                visible: visible, scrollSlot: $scrollSlot
            )
            .frame(maxHeight: .infinity)

            // A figure that fits the roll has nowhere to scroll to.
            if columns > visible {
                PatternMinimap(
                    slots: slots, keyCount: keyCount, visible: visible,
                    scrollSlot: $scrollSlot, shown: shown
                )
                .frame(height: 44)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            visible = max(4, min(Self.maxVisible, Int((width - Self.rollChrome) / PerformanceGraph.minColumn)))
        }
    }
}

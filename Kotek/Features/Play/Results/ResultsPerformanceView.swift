//
//  ResultsPerformanceView.swift
//  Kotek
//
//  The results screen's left column: the percentage graph with a minimap of the
//  whole figure under it, or — behind the toggle, or while a stroke is held —
//  the piano roll. Both sit over the same minimap, and holding either shows the
//  other until the finger lifts.
//
//  The roll used to be the whole column. It is the detail now: it says which
//  bilah a stroke is on, but said nothing about the strokes that
//  went well, and a long figure scrolled off with no sense of where you were.
//

import SwiftUI

struct ResultsPerformanceView: View {
    /// Both halves' slots — rests included — folded over every pass.
    let slots: [PatternSlotScore]
    let keyCount: Int

    /// Which view the column rests on; the other shows only while held.
    @State private var showsRoll = false
    @State private var scrollSlot = -0.5
    /// The stroke held on the graph, outlined on the roll it brings up.
    @State private var held: PatternSlotScore?
    @State private var visible = Self.maxVisible
    /// A finger has held still on the graph or the roll long enough to count as
    /// a hold rather than the start of a scroll. One state for both: only one
    /// of the two takes touches at a time.
    @GestureState private var holding = false

    /// Four beat groups a screenful, at most — fewer when the column is too
    /// narrow to give each slot `minSlotWidth`.
    private static let maxVisible = 16
    /// How long, and within how far, a finger must stay put to count as a hold.
    /// A scroll begins by moving, so it never gets this far — the peek used to
    /// open on any slow drag, because the chart's own selection has no slop.
    private static let holdTime = 0.4
    /// The graph's own selection has waited before it reports, so it needs
    /// less on top.
    private static let graphConfirm = Duration.milliseconds(250)
    private static let holdSlop: CGFloat = 6
    private static let minSlotWidth: CGFloat = 26
    /// The roll's bilah numbers, which its slots do not get.
    private static let rollLabelWidth: CGFloat = 28

    private var columns: Int {
        (slots.map(\.slot).max() ?? -1) + 1
    }

    private var showingRoll: Bool {
        showsRoll != (holding || held != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Performance", color: Theme.stone)
                Spacer()
                Button(showsRoll ? "Graph" : "Details") {
                    showsRoll.toggle()
                    held = nil
                }
                .buttonStyle(.kajar)
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(Theme.terracotta)
            }

            // Both stay in the tree. Holding one shows the other for as long as
            // the finger is down, and that finger belongs to the view it went
            // down on — swap that view out and the release is never seen, so
            // the peek would never end.
            ZStack {
                PercentageGraph(
                    slots: slots, visible: visible, scrollSlot: $scrollSlot,
                    onHold: { held = $0 }, holdTime: Self.graphConfirm
                )
                .opacity(showingRoll ? 0 : 1)
                .allowsHitTesting(!showsRoll)

                PerformanceGraph(
                    slots: slots, keyCount: keyCount, held: held,
                    visible: visible, scrollSlot: $scrollSlot
                )
                .opacity(showingRoll ? 1 : 0)
                .allowsHitTesting(showsRoll)
                .simultaneousGesture(hold)
            }
            .animation(.easeOut(duration: 0.12), value: showingRoll)
            .onChange(of: held) { follow(held) }
            .frame(maxHeight: .infinity)

            // A figure that fits the graph has nowhere to scroll to.
            if columns > visible {
                PatternMinimap(
                    slots: slots, keyCount: keyCount, visible: visible,
                    scrollSlot: $scrollSlot, cursor: held
                )
                .frame(height: 44)
            }

            HStack(spacing: 14) {
                legend("Polos", Theme.polosVoice)
                legend("Sangsih", Theme.sangsihVoice)
            }
            .font(.sans(12))
            .foregroundStyle(Theme.stone)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            visible = max(4, min(Self.maxVisible, Int((width - Self.rollLabelWidth) / Self.minSlotWidth)))
        }
    }

    /// Bring the held stroke into the window if it is outside it, by the least
    /// that shows it — centring it threw the view across the figure — so the
    /// roll never opens on a screenful that does not have it.
    private func follow(_ stroke: PatternSlotScore?) {
        guard let stroke else { return }
        let first = scrollSlot + 0.5
        guard Double(stroke.slot) < first || Double(stroke.slot) > first + Double(visible - 1) else { return }
        let target = Double(stroke.slot) < first ? Double(stroke.slot) : Double(stroke.slot - visible + 1)
        scrollSlot = min(max(target, 0), Double(max(columns - visible, 0))) - 0.5
    }

    private var hold: some Gesture {
        LongPressGesture(minimumDuration: Self.holdTime, maximumDistance: Self.holdSlop)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($holding) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 8)
            Text(label)
        }
    }
}

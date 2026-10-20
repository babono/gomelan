//
//  PercentageGraph.swift
//  Kotek
//
//  How much of each stroke of the figure landed, as one line per half.
//
//  The piano roll (`PerformanceGraph`) says WHERE a stroke slipped but only
//  puts a number on the ones that did, so a clean stroke and a nearly clean
//  one looked the same. This puts a number on every stroke and lets the dips
//  find themselves; the roll is one long-press away for the detail.
//
//  Swift Charts rather than a `Canvas` like the roll: scrolling, the axis and
//  VoiceOver's audio graph come with it, and `chartXSelection` on a scrollable
//  chart already waits for a long press, so holding to inspect does not fight
//  a swipe to scroll. It reports the selection at its own threshold, though,
//  and that fires on a slow scroll; `onHold` is only called once the finger
//  has stayed where it was for `holdTime` more (see the `.task` below).
//

import Charts
import SwiftUI

struct PercentageGraph: View {
    /// Both halves' slots — rests included — folded over every pass.
    let slots: [PatternSlotScore]
    /// How many slots one screenful shows.
    let visible: Int
    /// Leading edge of what is showing, in slot units. Shared with the minimap.
    @Binding var scrollSlot: Double
    /// The stroke under a held finger — the nearest one that has a percentage
    /// — and nil again when it lifts.
    let onHold: (PatternSlotScore?) -> Void
    /// How long the selection must sit still before it counts as a hold.
    let holdTime: Duration

    @State private var heldX: Double?
    @State private var confirmed = false

    private var columns: Int {
        (slots.map(\.slot).max() ?? -1) + 1
    }

    /// Struck slots that were judged. A rest, or a half that was never played,
    /// has no percentage to plot.
    private var points: [PatternSlotScore] {
        slots.filter { $0.landedRate != nil }
    }

    var body: some View {
        Chart {
            ForEach(points) { s in
                LineMark(
                    x: .value("Stroke", Double(s.slot)),
                    y: .value("Landed", (s.landedRate ?? 0) * 100),
                    series: .value("Half", s.half.title)
                )
                .foregroundStyle(by: .value("Half", s.half.title))
                // Monotone, not catmullRom: the curve never overshoots a dot, so
                // it cannot dip under 0% or rise over 100% between two strokes.
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))

                PointMark(x: .value("Stroke", Double(s.slot)), y: .value("Landed", (s.landedRate ?? 0) * 100))
                    .foregroundStyle(by: .value("Half", s.half.title))
                    .symbolSize(28)
            }

        }
        .chartForegroundStyleScale([
            KotekanHalf.polos.title: Theme.polosVoice,
            KotekanHalf.sangsih.title: Theme.sangsihVoice
        ])
        .chartLegend(.hidden)
        .chartYScale(domain: 0 ... 100)
        .chartXScale(domain: -0.5 ... Double(columns) - 0.5)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: domain)
        .chartScrollPosition(x: $scrollSlot)
        .chartXSelection(value: $heldX)
        .chartXAxis {
            // Numbered by beat, not by slot: a beat is four slots, ruled in the
            // gold the roll draws its beats in, and the slots between are
            // faint ticks. Numbering every slot read as a count of keys.
            AxisMarks(values: Array(0 ..< columns).map(Double.init)) { value in
                let slot = Int(value.as(Double.self) ?? 0)
                AxisGridLine().foregroundStyle(slot % 4 == 0 ? Theme.gold.opacity(0.35) : Theme.cream.opacity(0.07))
                AxisValueLabel {
                    if slot % 4 == 0 {
                        Text("\(slot / 4 + 1)")
                            .font(.sans(11, weight: .semibold))
                            .foregroundStyle(Theme.stone)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(Theme.cream.opacity(0.07))
                AxisValueLabel {
                    if let percent = value.as(Int.self) {
                        Text("\(percent)%")
                            .font(.sans(11, weight: .semibold))
                            .foregroundStyle(Theme.stone)
                    }
                }
            }
        }
        .padding(10)
        .background(Theme.deep.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.radius))
        .onChange(of: heldX) { onHold(confirmed ? nearest(heldX) : nil) }
        .task(id: heldX != nil) {
            confirmed = false
            guard heldX != nil else { return }
            // A scroll that began as a selection moves the chart under the
            // finger; a hold does not. Under a quarter of a slot is still.
            let origin = scrollSlot
            try? await Task.sleep(for: holdTime)
            guard !Task.isCancelled, abs(scrollSlot - origin) < 0.25 else { return }
            confirmed = true
            onHold(nearest(heldX))
        }
        .task(id: confirmed) {
            // Held at an edge, the chart scrolls on under the finger a little
            // at a time. The selection runs on past the plot when the finger
            // does, and snapping to the nearest stroke of the WHOLE figure
            // threw the view to the far end in one go.
            guard confirmed, columns > visible else { return }
            let step = 0.2
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(40))
                guard let x = heldX else { continue }
                let furthest = max(Double(columns) - domain - 0.5, scrollSlot)
                if x > scrollSlot + domain - 1 {
                    scrollSlot = min(scrollSlot + step, furthest)
                } else if x < scrollSlot + 1 {
                    scrollSlot = max(scrollSlot - step, -0.5)
                }
                onHold(nearest(heldX))
            }
        }
    }

    private var domain: Double {
        Double(min(visible, columns))
    }

    /// The nearest stroke that has a percentage; the finger can be anywhere
    /// along a rest, or past the edge of the plot — held to the slots on
    /// screen, so a finger dragged off the side never picks a far stroke.
    private func nearest(_ x: Double?) -> PatternSlotScore? {
        guard let raw = x else { return nil }
        let x = min(max(raw, scrollSlot + 0.5), scrollSlot + domain - 0.5)
        return points.min { abs(Double($0.slot) - x) < abs(Double($1.slot) - x) }
    }
}

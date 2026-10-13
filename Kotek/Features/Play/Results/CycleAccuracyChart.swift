//
//  CycleAccuracyChart.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// Average accuracy of each stroke of the figure, laid out across one gong
/// cycle, with the cycle split into quarters.
///
/// It used to be accuracy per PASS — one point per cycle over the session.
/// That showed whether a session improved, which looping practice nearly
/// always does, and said nothing about what to practise next. Laying the
/// strokes out where they fall in the cycle shows which stretch of the figure
/// keeps slipping, and that is something a player can go and work on.
///
/// Bars sit at the stroke's TIME, not its index, so the rests in a figure show
/// as gaps — the shape on screen is the shape of the kotekan.
///
/// A Canvas rather than a chart library: a few dozen rectangles sitting on the
/// same warm ground as everything else.
struct CycleAccuracyChart: View {
    let strokes: [StrokeAverage]
    let parts: [CyclePartAverage]
    let cycleMs: Int
    /// The quarter to shade, if one is clearly behind the rest.
    let weakest: CyclePart?

    var body: some View {
        Canvas { ctx, size in
            let plot = CGRect(x: 6, y: 6, width: size.width - 12, height: size.height - 24)
            guard plot.width > 0, plot.height > 0, cycleMs > 0 else { return }

            ctx.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: Theme.radius),
                with: .color(Theme.deep.opacity(0.55))
            )

            let quarterWidth = plot.width / CGFloat(CyclePart.allCases.count)

            if let weakest {
                let x = plot.minX + quarterWidth * CGFloat(weakest.rawValue)
                ctx.fill(
                    Path(CGRect(x: x, y: plot.minY, width: quarterWidth, height: plot.height)),
                    with: .color(Theme.miss.opacity(0.12))
                )
            }

            // Quarter rules (0–100%)
            for f in [0.25, 0.5, 0.75] {
                let y = plot.maxY - plot.height * f
                ctx.fill(
                    Path(CGRect(x: plot.minX, y: y, width: plot.width, height: 0.5)),
                    with: .color(Theme.charcoal.opacity(0.10))
                )
            }

            // Quarter dividers and labels: "Opening 92%".
            for part in CyclePart.allCases {
                let x = plot.minX + quarterWidth * CGFloat(part.rawValue)
                if part.rawValue > 0 {
                    ctx.fill(
                        Path(CGRect(x: x, y: plot.minY, width: 0.5, height: plot.height)),
                        with: .color(Theme.charcoal.opacity(0.18))
                    )
                }
                let avg = parts.first { $0.part == part }
                let isWeakest = part == weakest
                let label = avg.map { avg in
                    let pct = Text("\(Int((avg.accuracy * 100).rounded()))%").fontWeight(.semibold)
                    return Text("\(part.label) \(pct)")
                } ?? Text(part.label)
                ctx.draw(
                    label.font(.sans(10)).foregroundStyle(isWeakest ? Theme.miss : Theme.stone),
                    at: CGPoint(x: x + quarterWidth / 2, y: size.height - 9),
                    anchor: .center
                )
            }

            // R Bar width from the tightest spacing in the figure, so adjacent
            // R strokes never touch; capped so a sparse figure's bars stay bars.
            let times = strokes.map(\.timeMs).sorted()
            let minGap = zip(times, times.dropFirst()).map { $1 - $0 }.min() ?? cycleMs / 8
            let slot = plot.width * CGFloat(max(1, minGap)) / CGFloat(cycleMs)
            let barWidth = min(18, max(2, slot * 0.6))
            let lowest = strokes.min { $0.accuracy < $1.accuracy }?.stroke

            for s in strokes {
                // R Centred in its slot rather than on the slot's leading edge,
                // R so the first stroke is not half off the plot.
                let x = plot.minX + plot.width * CGFloat(s.timeMs) / CGFloat(cycleMs) + slot / 2
                let h = max(2, plot.height * min(1, max(0, s.accuracy)))
                let rect = CGRect(x: x - barWidth / 2, y: plot.maxY - h, width: barWidth, height: h)
                ctx.fill(
                    Path(roundedRect: rect, cornerRadius: min(3, barWidth / 2)),
                    with: .color(s.stroke == lowest && strokes.count > 1 ? Theme.miss : Theme.terracotta)
                )
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let quarters = parts
            .map { "\($0.part.label) \(Int(($0.accuracy * 100).rounded())) percent" }
            .joined(separator: ", ")
        if let weakest {
            return "Average accuracy by quarter of the cycle: \(quarters). Weakest: \(weakest.label)."
        }
        return "Average accuracy by quarter of the cycle: \(quarters)."
    }
}

//
//  PerformanceGraph.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// Accuracy per pass, drawn as one line over the passes played.
/// A Canvas rather than a chart library: four strokes over a handful of
/// points sitting on the same warm ground as everything else.
struct PerformanceGraph: View {
    let cycles: [CycleScore]
    let best: ClosedRange<Int>

    var body: some View {
        Canvas { ctx, size in
            let plot = CGRect(x: 6, y: 6, width: size.width - 12, height: size.height - 20)
            guard plot.width > 0, plot.height > 0 else { return }

            ctx.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: Theme.radius),
                with: .color(Theme.deep.opacity(0.55))
            )

            // Quarter rules (0–100%)
            for f in [0.25, 0.5, 0.75] {
                let y = plot.maxY - plot.height * f
                ctx.fill(
                    Path(CGRect(x: plot.minX, y: y, width: plot.width, height: 0.5)),
                    with: .color(Theme.charcoal.opacity(0.10))
                )
            }

            guard cycles.count > 1 else {
                // One pass is a point, not a line.
                if let only = cycles.first {
                    let p = CGPoint(x: plot.midX, y: plot.maxY - plot.height * only.accuracy)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                        with: .color(Theme.terracotta)
                    )
                }
                return
            }

            func point(_ i: Int) -> CGPoint {
                let t = Double(i) / Double(cycles.count - 1)
                return CGPoint(
                    x: plot.minX + plot.width * t,
                    y: plot.maxY - plot.height * min(1, max(0, cycles[i].accuracy))
                )
            }

            // The window the headline came from, shaded behind the line.
            let lo = point(best.lowerBound).x, hi = point(best.upperBound).x
            ctx.fill(
                Path(CGRect(x: lo, y: plot.minY, width: max(2, hi - lo), height: plot.height)),
                with: .color(Theme.terracotta.opacity(0.14))
            )

            var line = Path()
            line.move(to: point(0))
            for i in 1 ..< cycles.count {
                line.addLine(to: point(i))
            }
            ctx.stroke(line, with: .color(Theme.terracotta), lineWidth: 2)

            // Dots only when there is room for them to be distinct.
            if cycles.count <= 40 {
                for i in cycles.indices {
                    let p = point(i)
                    let inBest = best.contains(i)
                    let r: CGFloat = inBest ? 3 : 2
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                        with: .color(inBest ? Theme.cream : Theme.terracotta)
                    )
                }
            }

            ctx.draw(
                Text("Cycles").font(.sans(10)).foregroundStyle(Theme.stone),
                at: CGPoint(x: plot.maxX, y: size.height - 7),
                anchor: .trailing
            )
        }
    }
}

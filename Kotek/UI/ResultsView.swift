//
//  ResultsView.swift
//  Kotek
//
//  The score, shown only when the player ends a session (PRD §4 Flow C, §8).
//  Practice loops indefinitely and never interrupts, so this is the one moment
//  the app says anything about how it went — and the tone stays encouraging:
//  the headline is your BEST stretch, not your average, then where it slipped,
//  framed as observations rather than failures.
//
//  Why a best: a session that runs until you stop it can only drag an average
//  down, since every warm-up pass and every stretch where you paused to look at
//  your hands stays in it forever. A number that gets worse the longer you
//  practise punishes the thing this screen exists to encourage. See
//  `SongResult.best`.
//

import SwiftUI

struct ResultsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if let result = app.lastResult {
            VStack(spacing: 0) {
                header(result)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 24) {
                        if let best = result.best {
                            HStack(alignment: .top, spacing: 28) {
                                headline(best)
                                performance(result, best: best)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if !result.breakdown.isEmpty { slipped(result) }
                        } else {
                            tooShort
                        }

                        bottomBar
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)
                }
            }
        } else {
            Color.clear.onAppear { app.backToKotekan() }
        }
    }

    private func header(_ result: SongResult) -> some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel("Result", color: Theme.stone)
                Spacer()
                Text(result.subtitle)
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(Theme.terracotta)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 16)
            Rectangle().fill(Theme.charcoal.opacity(0.12)).frame(height: 1)
        }
    }

    // MARK: - The numbers

    private func headline(_ best: ScoringWindow) -> some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Accuracy", color: Theme.stone)
                Text(String(format: "%.2f%%", best.accuracy * 100))
                    .font(.serif(56))
                    .foregroundStyle(Theme.charcoal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                recordLine
            }

            VStack(alignment: .leading, spacing: 14) {
                stat("On the beat", "\(best.onBeat)")
                stat("Mistakes", "\(best.mistakes)")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// What this session did to the figure's record.
    ///
    /// Records need a FULL eight-cycle window, so a short session says so
    /// rather than silently not counting — "your best three cycles" is a real
    /// number and a fake record, and a player who stopped early deserves to
    /// know which one they are looking at.
    @ViewBuilder
    private var recordLine: some View {
        if (app.lastResult?.cycles.count ?? 0) < SongResult.scoringWindow {
            label("Needs \(SongResult.scoringWindow) cycles to set a record", Theme.stone)
        } else if app.lastSetRecord, let previous = app.previousRecord {
            label(String(format: "New record · was %.1f%%", previous * 100), Theme.hit)
        } else if app.lastSetRecord {
            label("First record on this gangsa", Theme.hit)
        } else if let best = currentRecord {
            label(String(format: "Your best is %.1f%%", best * 100), Theme.stone)
        }
    }

    /// The record as it stands NOW — which, if this session beat it, is this
    /// session's own score. Only read on the path where it did not.
    private var currentRecord: Double? {
        guard let k = app.selectedKotekan else { return nil }
        return app.profile.record(kotekanId: k.id,
                                  half: app.chosenHalf.rawValue,
                                  tempo: app.tempoScale)?.accuracy
    }

    private func label(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.sans(13, weight: .medium))
            .foregroundStyle(color)
            .padding(.top, 6)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(label, color: Theme.stone)
            Text(value).font(.serif(26)).foregroundStyle(Theme.charcoal)
        }
    }

    // MARK: - The graph

    /// Accuracy pass by pass, with the stretch the headline came from lit.
    ///
    /// Showing WHICH passes scored is most of the value here: a line that climbs
    /// and holds says the figure went into the hands, and a line that spikes once
    /// says it did not. The lit window is also the only honest way to display a
    /// best — otherwise the number above looks cherry-picked, which it is, and
    /// this shows exactly where from.
    private func performance(_ result: SongResult, best: ScoringWindow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Performance", color: Theme.stone)

            PerformanceGraph(cycles: result.cycles, best: best.range)
                .frame(height: 132)
                .frame(maxWidth: .infinity)

            HStack {
                Text("\(result.cycles.count) cycle\(result.cycles.count == 1 ? "" : "s")")
                Spacer()
                Text("best \(best.range.lowerBound + 1)–\(best.range.upperBound + 1)")
                    .foregroundStyle(Theme.terracotta)
            }
            .font(.sans(12))
            .foregroundStyle(Theme.stone)
        }
    }

    private func slipped(_ result: SongResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Where it slipped", color: Theme.stone)
            ForEach(result.breakdown) { row in
                HStack(spacing: 12) {
                    Text(bilahLabel(row.keyIndex, count: app.profile.keys.count))
                        .font(.serif(18, weight: .semibold))
                        .foregroundStyle(Theme.charcoal)
                        .frame(width: 26, alignment: .leading)
                    StatBar(fraction: row.accuracy,
                            color: row.accuracy >= 0.7 ? Theme.terracotta : Theme.charcoal.opacity(0.6))
                    Text(row.note)
                        .font(.sans(13))
                        .foregroundStyle(Theme.stone)
                        .frame(width: 140, alignment: .trailing)
                }
            }
        }
    }

    /// Ended before a single pass came round. Not a score of zero — nothing was
    /// measured, and saying 0% for a session that was stopped during the
    /// count-in would be a lie about the playing rather than about the length.
    private var tooShort: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Not enough to score")
                .font(.serif(34))
                .foregroundStyle(Theme.charcoal)
            Text("The figure has to come round at least once. Give it a full pass of the gong cycle and the score has something to measure.")
                .font(.sans(15))
                .foregroundStyle(Theme.stone)
                .lineSpacing(3)
                .frame(maxWidth: 460, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            PillButton(title: "Back", style: .outlined, tint: Theme.charcoal) {
                app.backToKotekan()
            }
            PillButton(title: "Retry", style: .filled, tint: Theme.terracotta) {
                app.retry()
            }
            Spacer()
        }
        .padding(.top, 4)
        .padding(.bottom, 16)
    }
}

/// Accuracy per pass, drawn as one line over the passes played.
///
/// A Canvas rather than a chart library: this is four strokes over a handful of
/// points and it has to sit on the same warm ground as everything else.
private struct PerformanceGraph: View {
    let cycles: [CycleScore]
    let best: ClosedRange<Int>

    var body: some View {
        Canvas { ctx, size in
            let plot = CGRect(x: 6, y: 6, width: size.width - 12, height: size.height - 20)
            guard plot.width > 0, plot.height > 0 else { return }

            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: Theme.radius),
                     with: .color(Theme.deep.opacity(0.55)))

            // Quarter rules. Unlabelled: the axis is 0–100% by definition and a
            // strip this small cannot afford four numbers down its side.
            for f in [0.25, 0.5, 0.75] {
                let y = plot.maxY - plot.height * f
                ctx.fill(Path(CGRect(x: plot.minX, y: y, width: plot.width, height: 0.5)),
                         with: .color(Theme.charcoal.opacity(0.10)))
            }

            guard cycles.count > 1 else {
                // One pass is a point, not a line.
                if let only = cycles.first {
                    let p = CGPoint(x: plot.midX, y: plot.maxY - plot.height * only.accuracy)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                             with: .color(Theme.terracotta))
                }
                return
            }

            func point(_ i: Int) -> CGPoint {
                let t = Double(i) / Double(cycles.count - 1)
                return CGPoint(x: plot.minX + plot.width * t,
                               y: plot.maxY - plot.height * min(1, max(0, cycles[i].accuracy)))
            }

            // The window the headline came from, shaded behind the line.
            let lo = point(best.lowerBound).x, hi = point(best.upperBound).x
            ctx.fill(Path(CGRect(x: lo, y: plot.minY, width: max(2, hi - lo), height: plot.height)),
                     with: .color(Theme.terracotta.opacity(0.14)))

            var line = Path()
            line.move(to: point(0))
            for i in 1..<cycles.count { line.addLine(to: point(i)) }
            ctx.stroke(line, with: .color(Theme.terracotta), lineWidth: 2)

            // Dots only when there is room for them to be distinct.
            if cycles.count <= 40 {
                for i in cycles.indices {
                    let p = point(i)
                    let inBest = best.contains(i)
                    let r: CGFloat = inBest ? 3 : 2
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                             with: .color(inBest ? Theme.cream : Theme.terracotta))
                }
            }

            ctx.draw(Text("Cycles").font(.sans(10)).foregroundStyle(Theme.stone),
                     at: CGPoint(x: plot.maxX, y: size.height - 7), anchor: .trailing)
        }
    }
}

//
//  PerformanceGraph.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// The kotekan as a piano roll — every bilah of the gangsa for rows, ONE pass
/// of the figure across — with the share of each stroke that landed written on it.
///
/// One pass because that is all the figure is: practice loops it, the same
/// slots come round every time, and every pass is folded onto them. So the
/// graph is as wide as the figure needs and no wider; it does not stretch a
/// sixteen-slot kotekan across a landscape screen.
///
/// A long figure scrolls sideways instead of being squeezed. Fitting every
/// slot into the half-screen column was tried first: a 32-slot pattern came
/// out ten points a slot, the blocks turned into slivers and the percentages
/// had no room to show. The bilah numbers stay pinned outside the scroll so a
/// row can still be read halfway along.
///
/// Both halves, interlocked, in the editor's colours (`PianoRollView`): the
/// figure only reads as itself with polos and sangsih together. Practice can
/// switch sides mid-session, so either half may have been played, or both. A
/// half that was never played stays on the roll, dimmed, as the shape you were
/// playing against — and gets no marks, because it was never judged.
///
/// Behind the blocks, faint, ONE half's landed share as a curve — bottom 0%,
/// top 100%, read off the scale on the right — picked with the switch above
/// the roll. That half gets the chips; the other is dimmed, as the shape it was
/// played against. Both curves at once, with both halves' chips, was too much
/// to read over the blocks.
///
/// Numbered along the bottom by beat (four slots), not by stroke: a stroke
/// number under every slot read as a second axis to decode.
///
/// History, each tried and replaced:
///  - a line of accuracy per cycle — showed whether the session warmed up,
///    hid the stroke that fails every time round (see `PatternSlotScore`);
///  - a bar per slot, height the slip rate — located the slips but threw the
///    figure away, so "stroke 7" meant nothing without counting it out;
///  - one line through the half's bilah — closer, but a single half reads as
///    a zig-zag rather than a kotekan, and its rows were only the bilah used;
///  - the percentage as its own chart, with this roll a hold or a toggle away
///    — two views of one session, and the hold kept catching scrolls.
struct PerformanceGraph: View {
    /// Both halves' slots — rests included — folded over every pass.
    let slots: [PatternSlotScore]
    /// Every bilah of the gangsa, so the figure sits where it is played.
    let keyCount: Int
    /// The half whose curve and chips are drawn; the other is dimmed.
    let shown: KotekanHalf
    /// How many slots one screenful shows — shared with the minimap, so both
    /// agree on what the window covers.
    let visible: Int
    /// Leading edge of what is showing, in slot units with the first slot's
    /// centre at 0.5 (so -0.5 is the start). Shared with the minimap.
    @Binding var scrollSlot: Double

    @State private var position = ScrollPosition(edge: .leading)
    /// How far the roll can scroll, as the scroll view itself reports it.
    @State private var range: ClosedRange<CGFloat> = 0 ... 0
    /// The position this roll last reported itself. A change equal to it came
    /// from this roll's own scrolling and must not be written back: doing so
    /// fought every drag, and the roll would not scroll at all.
    @State private var reported = -0.5

    private static let labelWidth: CGFloat = 28
    /// The 0 / 50 / 100% scale for the curve, pinned like the bilah numbers.
    static let scaleWidth: CGFloat = 34
    /// The beat numbers under the roll.
    private static let beatHeight: CGFloat = 16
    /// A slot never gets wider than this: a short figure stays compact.
    private static let maxColumn: CGFloat = 44
    /// Also the width the percentages need to be drawn at all (see `draw`).
    /// `visible` is chosen so a slot is never narrower than this.
    /// "100%" at 8 pt is about 20 pt wide; 4 more keeps two neighbours'
    /// numbers from touching.
    /// The one place this width is set: the results column sizes its window
    /// from it too, so the slots it asks for are never narrower than this.
    static let minColumn: CGFloat = 28

    private var columns: Int {
        (slots.map(\.slot).max() ?? -1) + 1
    }

    private var rows: Int {
        max(keyCount, (slots.compactMap(\.keyIndex).max() ?? 0) + 1)
    }

    var body: some View {
        GeometryReader { geo in
            let space = max(0, geo.size.width - Self.labelWidth - Self.scaleWidth)
            let fits = columns <= visible
            // Exactly `visible` slots across the space when it scrolls, so the
            // minimap's window is the width of what is on screen.
            let column = fits
                ? min(Self.maxColumn, space / CGFloat(max(columns, 1)))
                : space / CGFloat(max(visible, 1))
            let rollWidth = CGFloat(columns) * column

            // The bilah numbers and the % scale are bars over the scroll, not
            // columns beside it: the roll slides under them and the system's
            // soft scroll edge blurs it away there, where a column beside the
            // scroll cut every block off at a hard line.
            ScrollView(.horizontal, showsIndicators: false) {
                Canvas { ctx, size in draw(ctx, size) }
                    .frame(width: rollWidth)
            }
            .safeAreaBar(edge: .leading, spacing: 0) {
                Canvas { ctx, size in drawLabels(ctx, size) }
                    .frame(width: Self.labelWidth)
            }
            .safeAreaBar(edge: .trailing, spacing: 0) {
                Canvas { ctx, size in drawScale(ctx, size) }
                    .frame(width: Self.scaleWidth)
            }
            .scrollEdgeEffectStyle(.soft, for: .horizontal)
            .scrollPosition($position)
            .scrollDisabled(fits)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            // Offsets count from the leading bar's edge, which the content
            // starts behind; slots count from the content's own start.
            // Position is the share of the way from the first screenful to
            // the last, from the scroll view's own offset range — both ways.
            // Working it out from slot widths and the bars' insets came up
            // short at the right end; jumping to the edge there to make up
            // for it snapped.
            .onScrollGeometryChange(for: ClosedRange<CGFloat>.self) { g in
                // `containerSize` is the width between the bars, insets already
                // out (measured: 298 of a 360 pt roll with 28 + 34 pt bars), so
                // the last offset is content minus container, from -leading.
                // Adding the trailing inset back overshot by both bars, and the
                // minimap stopped short of its end.
                let lowest = -g.contentInsets.leading
                return lowest ... max(lowest, lowest + g.contentSize.width - g.containerSize.width)
            } action: { _, new in
                range = new
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
                let span = range.upperBound - range.lowerBound
                guard span > 0 else { return }
                // Clamped: on first layout the offset moves for the bars'
                // insets before the range does, and read a slot past the start.
                let share = min(max(Double((x - range.lowerBound) / span), 0), 1)
                let slot = share * Double(max(columns - visible, 0)) - 0.5
                reported = slot
                if abs(slot - scrollSlot) > 0.01 { scrollSlot = slot }
            }
            .onChange(of: scrollSlot, initial: true) {
                guard abs(scrollSlot - reported) > 0.01 else { return }
                let screens = Double(max(columns - visible, 0))
                guard screens > 0 else { return }
                let share = CGFloat(min(max((scrollSlot + 0.5) / screens, 0), 1))
                // `scrollTo(x:)` is measured from where the content starts,
                // past the leading bar (measured: x 655.67 gave offset 627.67
                // with a 28 pt bar) — not in `contentOffset`'s terms. Passing
                // an offset left the roll a bar short, which it then read back
                // to the minimap, so the window jumped and never reached the end.
                position.scrollTo(x: share * (range.upperBound - range.lowerBound))
            }
            .frame(width: Self.labelWidth + min(rollWidth, space) + Self.scaleWidth)
            .background(Theme.deep.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.radius))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
    }

    /// The bilah numbers, top row highest — outside the scroll so they stay put.
    /// Plain 1…n: `bilahLabel` calls the top key "1·", which on this screen read
    /// as the same number twice.
    private func drawLabels(_ ctx: GraphicsContext, _ size: CGSize) {
        let rowHeight = (size.height - Self.beatHeight) / CGFloat(rows)
        for key in 0 ..< rows {
            ctx.draw(
                Text("\(key + 1)").font(.sans(11, weight: .semibold)).foregroundStyle(Theme.stone),
                at: CGPoint(x: size.width / 2 + 2, y: CGFloat(rows - 1 - key) * rowHeight + rowHeight / 2)
            )
        }
    }

    /// The curve's scale, in the same faint type as the bilah numbers.
    private func drawScale(_ ctx: GraphicsContext, _ size: CGSize) {
        let height = size.height - Self.beatHeight
        for (label, y) in [("100%", 7.0), ("50%", height / 2), ("0%", height - 7)] {
            ctx.draw(
                Text(label).font(.sans(10, weight: .semibold)).foregroundStyle(Theme.stone),
                at: CGPoint(x: size.width / 2 - 2, y: y)
            )
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        guard columns > 0 else { return }
        let roll = CGRect(x: 0, y: 0, width: size.width, height: size.height - Self.beatHeight)
        let origin = roll.minX
        let column = roll.width / CGFloat(columns)
        let rowHeight = roll.height / CGFloat(rows)
        func rowY(_ key: Int) -> CGFloat {
            roll.minY + CGFloat(rows - 1 - key) * rowHeight
        }
        func colX(_ slot: Int) -> CGFloat {
            origin + CGFloat(slot) * column
        }

        // Rows: alternate bands, top row highest.
        for key in 0 ..< rows where (rows - 1 - key) % 2 == 1 {
            ctx.fill(
                Path(CGRect(x: roll.minX, y: rowY(key), width: roll.width, height: rowHeight)),
                with: .color(Theme.cream.opacity(0.03))
            )
        }

        // Columns: every slot faint, every beat-group of four in gold, as the
        // editor draws them, so a stroke can be found by counting.
        for slot in 0 ... columns {
            // The closing line is a beat too, whatever the figure's length:
            // it marks where the cycle comes round.
            let strong = slot % 4 == 0 || slot == columns
            let width: CGFloat = strong ? 1.5 : 1
            // Drawn inside the roll: at its right edge the line started past
            // the canvas and never showed.
            ctx.fill(
                Path(CGRect(x: min(colX(slot), roll.maxX - width), y: roll.minY, width: width, height: roll.height)),
                with: .color(strong ? Theme.gold.opacity(0.35) : Theme.cream.opacity(0.07))
            )
        }
        for slot in stride(from: 0, to: columns, by: 4) {
            ctx.draw(
                Text("\(slot / 4 + 1)").font(.sans(11, weight: .semibold)).foregroundStyle(Theme.stone),
                at: CGPoint(x: colX(slot) + 4, y: roll.maxY + Self.beatHeight / 2),
                anchor: .leading
            )
        }

        Self.drawCurve(slots, shown: shown, ctx, roll, origin: origin, column: column)

        /// The figure, the dimmed strokes underneath so a stroke both halves
        /// share cannot hide the one that is being read.
        func lit(_ s: PatternSlotScore) -> Bool {
            s.half == shown && s.landedRate != nil
        }
        for s in slots.sorted(by: { !lit($0) && lit($1) }) {
            guard let key = s.keyIndex else { continue }
            let rect = CGRect(
                x: colX(s.slot) + 1.5, y: rowY(key) + 2,
                width: max(4, column - 3), height: rowHeight - 4
            )
            let block = Path(roundedRect: rect, cornerRadius: 4)
            let voice = s.half == .polos ? Theme.polosVoice : Theme.sangsihVoice
            guard lit(s), let rate = s.landedRate else {
                ctx.fill(block, with: .color(voice.opacity(0.25)))
                continue
            }
            ctx.fill(block, with: .color(voice.opacity(0.9)))
            ctx.stroke(block, with: .color(Theme.cream.opacity(0.5)), lineWidth: 1)
            // A share, not "5/10": the counts depend on how long you played,
            // so 5/5 and 5/10 had to be divided in your head before two
            // strokes could be compared. The share that LANDED, so it reads
            // like every other score in the app. Above the block, as it
            // always was, or below it on the top row — and in no colour but
            // the cream of the rest of the graph: the number is the rating,
            // and the stripes and slip colours it used to sit beside are gone.
            // Above the block, or below it on the top row. Bare text, no
            // backing chip.
            if column >= Self.minColumn {
                ctx.draw(
                    Text("\(Int((rate * 100).rounded()))%")
                        .font(.sans(8, weight: .semibold))
                        .foregroundStyle(Theme.cream),
                    at: CGPoint(x: rect.midX, y: rect.minY >= 12 ? rect.minY - 7 : rect.maxY + 7)
                )
            }
        }
    }

    /// The shown half's landed share, smoothed through each of its strokes,
    /// with a faint fill under it. Catmull-Rom with its handles held inside the
    /// roll, so the curve never swings past 0% or 100% between two strokes.
    /// Shared with the minimap, which draws the same curve under its strip.
    static func drawCurve(
        _ slots: [PatternSlotScore], shown: KotekanHalf, _ ctx: GraphicsContext, _ roll: CGRect,
        origin: CGFloat = 0, column: CGFloat, lineWidth: CGFloat = 3
    ) {
        let strokes = slots
            .filter { $0.half == shown }
            .compactMap { s in
                s.landedRate.map { CGPoint(
                    x: origin + (CGFloat(s.slot) + 0.5) * column,
                    y: roll.minY + roll.height * (1 - $0)
                ) }
            }
        guard let first = strokes.first, let last = strokes.last else { return }
        // Out to both edges level with the end strokes, as points of the same
        // curve: a straight line joined on there made a kink at each end.
        let points = [CGPoint(x: roll.minX, y: first.y)] + strokes + [CGPoint(x: roll.maxX, y: last.y)]
        func clamp(_ y: CGFloat) -> CGFloat {
            min(max(y, roll.minY), roll.maxY)
        }

        var line = Path()
        line.move(to: points[0])
        for i in 0 ..< points.count - 1 {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(
                i + 2,
                points.count - 1
            )]
            line.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: clamp(p1.y + (p2.y - p0.y) / 6)),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: clamp(p2.y - (p3.y - p1.y) / 6))
            )
        }
        var area = line
        area.addLine(to: CGPoint(x: roll.maxX, y: roll.maxY))
        area.addLine(to: CGPoint(x: roll.minX, y: roll.maxY))
        area.closeSubpath()

        let voice = shown == .polos ? Theme.polosVoice : Theme.sangsihVoice
        var half = Path()
        half.move(to: CGPoint(x: roll.minX, y: roll.midY))
        half.addLine(to: CGPoint(x: roll.maxX, y: roll.midY))
        ctx.stroke(half, with: .color(Theme.gold.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        ctx.fill(area, with: .color(voice.opacity(0.1)))
        ctx.stroke(
            line,
            with: .color(voice.opacity(0.4)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }
}

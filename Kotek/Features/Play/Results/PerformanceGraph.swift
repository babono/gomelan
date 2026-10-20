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
/// No stroke numbers along the bottom. They were there so "stroke 7" in the
/// feedback could be counted out, but the block already marks the
/// stroke, and a row of numbers under a melody read as a second axis to decode.
///
/// History, each tried and replaced:
///  - a line of accuracy per cycle — showed whether the session warmed up,
///    hid the stroke that fails every time round (see `PatternSlotScore`);
///  - a bar per slot, height the slip rate — located the slips but threw the
///    figure away, so "stroke 7" meant nothing without counting it out;
///  - one line through the half's bilah — closer, but a single half reads as
///    a zig-zag rather than a kotekan, and its rows were only the bilah used.
struct PerformanceGraph: View {
    /// Both halves' slots — rests included — folded over every pass.
    let slots: [PatternSlotScore]
    /// Every bilah of the gangsa, so the figure sits where it is played.
    let keyCount: Int
    /// A stroke to outline: the one held on the percentage graph to get here.
    var held: PatternSlotScore?
    /// How many slots one screenful shows — shared with the graph and the
    /// minimap, so all three agree on what the window covers.
    let visible: Int
    /// Leading edge of what is showing, in the percentage graph's slot units
    /// (its origin is -0.5). Shared with the minimap.
    @Binding var scrollSlot: Double

    @State private var position = ScrollPosition(edge: .leading)

    private static let labelWidth: CGFloat = 28
    /// A slot never gets wider than this: a short figure stays compact.
    private static let maxColumn: CGFloat = 44
    /// Also the width the percentage chips need to be drawn at all (see `draw`).
    /// `visible` is chosen so a slot is never narrower than this.
    private static let minColumn: CGFloat = 26

    private var columns: Int {
        (slots.map(\.slot).max() ?? -1) + 1
    }

    private var rows: Int {
        max(keyCount, (slots.compactMap(\.keyIndex).max() ?? 0) + 1)
    }

    var body: some View {
        GeometryReader { geo in
            let space = max(0, geo.size.width - Self.labelWidth)
            let fits = columns <= visible
            // Exactly `visible` slots across the space when it scrolls, so the
            // minimap's window is the width of what is on screen.
            let column = fits
                ? min(Self.maxColumn, space / CGFloat(max(columns, 1)))
                : space / CGFloat(max(visible, 1))
            let rollWidth = CGFloat(columns) * column

            HStack(spacing: 0) {
                Canvas { ctx, size in drawLabels(ctx, size) }
                    .frame(width: Self.labelWidth)
                ScrollView(.horizontal, showsIndicators: false) {
                    Canvas { ctx, size in draw(ctx, size) }
                        .frame(width: rollWidth)
                }
                .scrollPosition($position)
                .scrollDisabled(fits)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
                    let slot = Double(x / column) - 0.5
                    if abs(slot - scrollSlot) > 0.01 { scrollSlot = slot }
                }
                .onChange(of: scrollSlot, initial: true) {
                    position.scrollTo(x: CGFloat(scrollSlot + 0.5) * column)
                }
            }
            .frame(width: Self.labelWidth + min(rollWidth, space))
            .background(Theme.deep.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.radius))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
    }

    /// The bilah numbers, top row highest — outside the scroll so they stay put.
    /// Plain 1…n: `bilahLabel` calls the top key "1·", which on this screen read
    /// as the same number twice.
    private func drawLabels(_ ctx: GraphicsContext, _ size: CGSize) {
        let rowHeight = size.height / CGFloat(rows)
        for key in 0 ..< rows {
            ctx.draw(
                Text("\(key + 1)").font(.sans(11, weight: .semibold)).foregroundStyle(Theme.stone),
                at: CGPoint(x: size.width / 2 + 2, y: CGFloat(rows - 1 - key) * rowHeight + rowHeight / 2)
            )
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        guard columns > 0 else { return }
        let roll = CGRect(origin: .zero, size: size)
        let column = roll.width / CGFloat(columns)
        let rowHeight = roll.height / CGFloat(rows)
        func rowY(_ key: Int) -> CGFloat {
            roll.minY + CGFloat(rows - 1 - key) * rowHeight
        }
        func colX(_ slot: Int) -> CGFloat {
            roll.minX + CGFloat(slot) * column
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
            let strong = slot % 4 == 0
            ctx.fill(
                Path(CGRect(x: colX(slot), y: roll.minY, width: strong ? 1.5 : 1, height: roll.height)),
                with: .color(strong ? Theme.gold.opacity(0.35) : Theme.cream.opacity(0.07))
            )
        }
        let played = Set(slots.filter { $0.attempts > 0 }.map(\.half))

        /// The figure, the half that was never played underneath so a stroke
        /// both halves share cannot hide the one that was judged.
        func layer(_ s: PatternSlotScore) -> Int {
            played.contains(s.half) ? 1 : 0
        }
        for s in slots.sorted(by: { layer($0) < layer($1) }) {
            guard let key = s.keyIndex else { continue }
            let rect = CGRect(
                x: colX(s.slot) + 1.5, y: rowY(key) + 2,
                width: max(4, column - 3), height: rowHeight - 4
            )
            let block = Path(roundedRect: rect, cornerRadius: 4)
            let voice = s.half == .polos ? Theme.polosVoice : Theme.sangsihVoice
            defer {
                if s == held { ctx.stroke(block, with: .color(Theme.gold), lineWidth: 3) }
            }

            guard let rate = s.landedRate else {
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
            if column >= Self.minColumn {
                let y = rect.minY >= 16 ? rect.minY - 9 : rect.maxY + 9
                chip(
                    "\(Int((rate * 100).rounded()))%",
                    color: Theme.cream,
                    at: CGPoint(x: rect.midX, y: y),
                    ctx,
                    size
                )
            }
        }
    }

    /// A count on a backing chip — bare text over the grid lines was unreadable.
    /// 8 pt with 2 pt of padding: at 10 pt and 4 pt a "100%" was wider than the
    /// narrowest slot and neighbouring chips ran into each other.
    private func chip(_ text: String, color: Color, at p: CGPoint, _ ctx: GraphicsContext, _ size: CGSize) {
        let label = ctx.resolve(Text(text).font(.sans(8, weight: .semibold)).foregroundStyle(color))
        let box = label.measure(in: size)
        ctx.fill(
            Path(roundedRect: CGRect(
                x: p.x - box.width / 2 - 2, y: p.y - box.height / 2 - 1,
                width: box.width + 4, height: box.height + 2
            ), cornerRadius: 4),
            with: .color(Theme.deep)
        )
        ctx.draw(label, at: p)
    }
}

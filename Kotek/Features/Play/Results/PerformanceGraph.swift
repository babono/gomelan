//
//  PerformanceGraph.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// The kotekan as a piano roll — every bilah of the gangsa for rows, ONE pass
/// of the figure across — with the strokes that slipped drawn differently.
///
/// One pass because that is all the figure is: practice loops it, the same
/// slots come round every time, and every pass is folded onto them. So the
/// graph is as wide as the figure needs and no wider; it does not stretch a
/// sixteen-slot kotekan across a landscape screen.
///
/// A long figure scrolls sideways instead of being squeezed. Fitting every
/// slot into the half-screen column was tried first: a 32-slot pattern came
/// out ten points a slot, the blocks turned into slivers and the slip counts
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
/// feedback could be counted out, but the striped block already marks the
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
    /// The stroke the feedback talks about first; given a heavier rim.
    let worst: PatternSlotScore?

    private static let labelWidth: CGFloat = 28
    /// A slot never gets wider than this: a short figure stays compact.
    private static let maxColumn: CGFloat = 44
    /// Nor narrower than this — past it the roll scrolls. Also the width the
    /// slip counts need to be drawn at all (see `draw`).
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
            let fits = CGFloat(columns) * Self.minColumn <= space
            let rollWidth = fits
                ? min(space, CGFloat(columns) * Self.maxColumn)
                : CGFloat(columns) * Self.minColumn

            HStack(spacing: 0) {
                Canvas { ctx, size in drawLabels(ctx, size) }
                    .frame(width: Self.labelWidth)
                ScrollView(.horizontal, showsIndicators: !fits) {
                    Canvas { ctx, size in draw(ctx, size) }
                        .frame(width: rollWidth)
                }
                .scrollDisabled(fits)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
            .frame(width: Self.labelWidth + min(rollWidth, space))
            .background(Theme.deep.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.radius))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
    }

    /// The bilah numbers, top row highest — outside the scroll so they stay put.
    private func drawLabels(_ ctx: GraphicsContext, _ size: CGSize) {
        let rowHeight = size.height / CGFloat(rows)
        for key in 0 ..< rows {
            ctx.draw(
                Text(bilahLabel(key, count: rows)).font(.sans(11, weight: .semibold)).foregroundStyle(Theme.stone),
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

        /// The figure. Unplayed half first, then clean strokes, then slips on
        /// top — a stroke both halves share must never hide the one that
        /// slipped under the one that did not.
        func layer(_ s: PatternSlotScore) -> Int {
            !played.contains(s.half) ? 0 : s.slips == 0 ? 1 : 2
        }
        for s in slots.sorted(by: { layer($0) < layer($1) }) {
            guard let key = s.keyIndex else { continue }
            let rect = CGRect(
                x: colX(s.slot) + 1.5, y: rowY(key) + 2,
                width: max(4, column - 3), height: rowHeight - 4
            )
            let block = Path(roundedRect: rect, cornerRadius: 4)
            let voice = s.half == .polos ? Theme.polosVoice : Theme.sangsihVoice

            switch layer(s) {
            case 0:
                ctx.fill(block, with: .color(voice.opacity(0.25)))
            case 1:
                ctx.fill(block, with: .color(voice.opacity(0.9)))
                ctx.stroke(block, with: .color(Theme.cream.opacity(0.5)), lineWidth: 1)
            default:
                // A different LOOK, not only a different colour: the block
                // keeps its half's colour — you still need to know which side
                // slipped — but is struck through with the slip's stripes and
                // rimmed in it. Filling it with the slip colour instead was
                // tried first, and lost the half.
                let slip = Self.color(s)
                ctx.fill(block, with: .color(voice.opacity(0.55)))
                var stripes = ctx
                stripes.clip(to: block)
                var x = rect.minX - rect.height
                while x < rect.maxX {
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: rect.maxY))
                    line.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                    stripes.stroke(line, with: .color(slip.opacity(0.9)), lineWidth: 2.5)
                    x += 7
                }
                ctx.stroke(block, with: .color(slip), lineWidth: s == worst ? 3 : 2)
                if column >= Self.minColumn {
                    // Above the block, or below it on the top row.
                    let y = rect.minY >= 16 ? rect.minY - 9 : rect.maxY + 9
                    // A share, not "5/10": the counts depend on how long you
                    // played, so 5/5 and 5/10 had to be divided in your head
                    // before two strokes could be compared. The share that
                    // LANDED, so it reads like every other score in the app —
                    // the slip share was tried first, and a stroke that never
                    // once landed read "100%".
                    chip("\(Int(((1 - s.slipRate) * 100).rounded()))%", color: slip, at: CGPoint(x: rect.midX, y: y), ctx, size)
                }
            }
        }
    }

    /// A count on a backing chip — bare text over the grid lines was unreadable.
    private func chip(_ text: String, color: Color, at p: CGPoint, _ ctx: GraphicsContext, _ size: CGSize) {
        let label = ctx.resolve(Text(text).font(.sans(10, weight: .semibold)).foregroundStyle(color))
        let box = label.measure(in: size)
        ctx.fill(
            Path(roundedRect: CGRect(
                x: p.x - box.width / 2 - 4, y: p.y - box.height / 2 - 1,
                width: box.width + 8, height: box.height + 2
            ), cornerRadius: 4),
            with: .color(Theme.deep)
        )
        ctx.draw(label, at: p)
    }

    /// Wrong bilah or missed, whichever this stroke did more of.
    static func color(_ s: PatternSlotScore) -> Color {
        s.wrongKey >= s.missed ? Theme.wrong : Theme.miss
    }
}

//
//  PatternMinimap.swift
//  Kotek
//
//  The whole figure, end to end, with a window on the part the graph above it
//  is showing.
//
//  Drag the window, or touch anywhere on the strip to bring it there: one
//  gesture does both, centring the window under the finger. The graph can be
//  scrolled by hand too, so the window is bound to the same position rather
//  than owning one.
//

import SwiftUI

struct PatternMinimap: View {
    let slots: [PatternSlotScore]
    let keyCount: Int
    /// How many slots the graph shows at once — the window's width.
    let visible: Int
    /// Leading edge of the graph, in slot units (the chart's own origin is -0.5).
    @Binding var scrollSlot: Double
    /// The held stroke, picked out on the strip.
    let cursor: PatternSlotScore?

    /// The strip's and the window's, the same: the window fills the strip's
    /// height, so at either end its corners sit in the strip's.
    private static let radius: CGFloat = 8

    private var columns: Int {
        (slots.map(\.slot).max() ?? -1) + 1
    }

    private var rows: Int {
        max(keyCount, (slots.compactMap(\.keyIndex).max() ?? 0) + 1)
    }

    var body: some View {
        GeometryReader { geo in
            let column = geo.size.width / CGFloat(max(columns, 1))
            let window = CGRect(
                x: CGFloat(scrollSlot + 0.5) * column, y: 0,
                width: CGFloat(visible) * column, height: geo.size.height
            )

            Canvas { ctx, size in draw(ctx, size) }
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: Self.radius)
                        .strokeBorder(Theme.gold, lineWidth: 2)
                        .background(Theme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: Self.radius))
                        .frame(width: window.width, height: window.height)
                        .offset(x: window.minX)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { drag in
                        let centre = Double(drag.location.x / column) - Double(visible) / 2
                        scrollSlot = min(max(centre, 0), Double(columns - visible)) - 0.5
                    }
                )
        }
        .background(Theme.deep.opacity(0.75), in: RoundedRectangle(cornerRadius: Self.radius))
        .clipShape(RoundedRectangle(cornerRadius: Self.radius))
        .accessibilityHidden(true) // the Details toggle is the way to every stroke
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        guard columns > 0 else { return }
        let column = size.width / CGFloat(columns)
        let rowHeight = size.height / CGFloat(rows)
        let played = Set(slots.filter { $0.attempts > 0 }.map(\.half))

        for s in slots {
            guard let key = s.keyIndex else { continue }
            let rect = CGRect(
                x: CGFloat(s.slot) * column + 0.5, y: CGFloat(rows - 1 - key) * rowHeight + 0.5,
                width: max(1, column - 1), height: max(1, rowHeight - 1)
            )
            let voice = s.half == .polos ? Theme.polosVoice : Theme.sangsihVoice
            // Paler the less of it landed.
            let fill = voice.opacity(!played.contains(s.half) ? 0.25 : 0.3 + 0.6 * (s.landedRate ?? 1))
            ctx.fill(Path(rect), with: .color(fill))
            if s == cursor {
                ctx.stroke(Path(rect.insetBy(dx: -1, dy: -1)), with: .color(Theme.cream), lineWidth: 1.5)
            }
        }
    }
}

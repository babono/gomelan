//
//  LaunchStage.swift
//  Kotek
//
//  What the splash and the landing screen share, in exactly the same place:
//  the wordmark with its script, and the gangsa table along the foot. The
//  splash sits OVER the landing screen and leaves by parting its curtains, so
//  anything that moved between the two would jump at the hand-over. One
//  layout, used by both, is what keeps it still.
//
//  Between the wordmark and the gangsa is the screen's own business: the
//  loading bar on the splash, the account choice on the landing screen.
//

import SwiftUI

struct LaunchStage<Middle: View>: View {
    /// False holds the gangsa still. It is a pure function of the clock, so
    /// when it starts it is on the same frame as any other copy.
    var animated = true
    @ViewBuilder var middle: Middle

    /// Across the bottom, a little narrower than the design's 73% — the
    /// landing screen's buttons have to clear the mallet swinging above it.
    static func tableWidth(in width: CGFloat) -> CGFloat {
        min(640, width * 0.66)
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let table = Self.tableWidth(in: w)

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    Spacer().frame(height: KotekWordmark.topInset(in: h))
                    KotekWordmark(width: KotekWordmark.width(in: w))
                    Spacer().frame(height: h * 0.035)
                    middle
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                GangsaTable(animated: animated)
                    .frame(width: table, height: GangsaTable.height(for: table))
            }
        }
        .ignoresSafeArea()
    }
}

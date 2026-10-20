//
//  CarouselFit.swift
//  Kotek
//
//  Sizing for the two pickers' card rails (Choose your gangsa, Choose your
//  kotekan). The side cards used to be a fixed 0.84-0.9 scale, which is wider
//  than a landscape phone's safe area leaves room for: the kotekan rail
//  clipped them at the safe edge and the gangsa rail let them run under the
//  Dynamic Island. Fitting them is a matter of making them smaller, so the
//  scale is worked out from the width instead.
//

import SwiftUI

enum CarouselFit {
    /// The space between the selected card and its neighbours that sets the
    /// side scale; `gap(width:card:)` is what it really ends up as.
    private static let nominalGap: CGFloat = 16

    /// The scale for the cards beside the selected one, such that their outer
    /// edges land exactly on the rail's edges: `card/2 + gap + side*card == width/2`.
    /// Clamped so a very narrow window doesn't shrink them to nothing and a very
    /// wide one doesn't leave them nearly full size with a hole beside them.
    static func sideScale(width: CGFloat, card: CGFloat) -> CGFloat {
        let room = width - card - 2 * nominalGap
        return (room / (2 * card)).clamped(to: 0.55, 0.9)
    }

    /// The visible space between the selected card and its neighbours. It is
    /// `nominalGap` until the scale hits its clamp, then it takes up the slack
    /// so the outer edges still land on the rail's edges on a wide phone.
    static func gap(width: CGFloat, card: CGFloat) -> CGFloat {
        (width - card) / 2 - sideScale(width: width, card: card) * card
    }
}

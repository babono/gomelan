//
//  PadScale.swift
//  Kotek
//
//  On iPad, the whole interface scaled up from the phone layout it was drawn
//  for. Every screen is set in fixed points for a landscape iPhone, so on an
//  iPad it came up phone-sized in the middle of a lot of empty brown —
//  correct, and visibly not made for the device.
//
//  Laying each screen out again for iPad would be a second app to keep in step
//  with the first. Scaling keeps one layout and makes it proportional: the
//  content is laid out at the iPad's size divided by the scale, then enlarged
//  to fill it — what Mac Catalyst's "scale interface to match iPad" does, the
//  other way round.
//

import SwiftUI
import UIKit

struct PadScale<Content: View>: View {
    @ViewBuilder var content: Content

    /// The iPhone 17's landscape screen, which every layout was tuned on.
    private static var reference: CGSize {
        CGSize(width: 874, height: 402)
    }

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            GeometryReader { geo in
                let s = Self.scale(for: geo.size)
                let insets = geo.safeAreaInsets
                content
                    // The screen's safe area, carried into the smaller layout:
                    // ignored, a footer sits under the home indicator; left to
                    // SwiftUI, a frame smaller than the screen gets none.
                    .safeAreaPadding(EdgeInsets(
                        top: insets.top / s,
                        leading: insets.leading / s,
                        bottom: insets.bottom / s,
                        trailing: insets.trailing / s
                    ))
                    .frame(width: geo.size.width / s, height: geo.size.height / s)
                    .scaleEffect(s)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()
        } else {
            content
        }
    }

    /// Bound by whichever side runs out first — the width, on every iPad — so
    /// nothing a phone shows is cut off. Never below 1: a window narrower than
    /// a phone (Split View, Stage Manager) keeps the phone's own sizes.
    static func scale(for size: CGSize) -> CGFloat {
        #if DEBUG
            // `-padScale 1.5`: try a scale on a simulator whose window is not
            // the shape of a real iPad's.
            let forced = UserDefaults.standard.double(forKey: "padScale")
            if forced > 0 { return forced }
        #endif
        return max(1, min(size.width / reference.width, size.height / reference.height))
    }
}

//
//  Theme.swift
//  gomelan
//
//  Overlay visual tokens (PRD §13.5). Peripheral legibility is the constraint —
//  large shapes, high contrast, no text during play.
//

import SwiftUI

enum Theme {
    // Overlay colours (§13.5)
    static let upcoming = Color(hex: 0x00D4FF)   // cyan
    static let hit = Color(hex: 0x00E676)        // green
    static let miss = Color(hex: 0xFF3B30)       // red
    static let wrong = Color(hex: 0xFFB300)      // amber
    static let gong = Color(hex: 0xFFC24B)

    // App chrome
    static let background = Color.black
    static let accent = Color(hex: 0x00D4FF)

    // Overlay geometry
    static let keyOutlineWidth: CGFloat = 3
    static let keyCornerRadius: CGFloat = 4
    static let approachTrackHeight: CGFloat = 56
    /// Fraction from the left where the strike line sits on the approach track.
    static let strikeLineFraction: CGFloat = 0.15
    /// Seconds of lookahead shown on the approach track.
    static let approachLookaheadSeconds: Double = 3
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

//
//  Theme.swift
//  gomelan
//
//  The visual design system (see design spec). Two worlds share one palette:
//   - "Paper" screens (welcome, setup, selection, results) sit on warm cream.
//   - "Stage" screens (framing, aligning, baseline, play) sit on warm ink so the
//     live camera and the guidance glow read clearly.
//
//  Colours: Primary terracotta #B35433, Secondary charcoal #4A443F,
//  Neutral cream #F2E8DF. Headlines are a Caslon-like serif (system New York);
//  body and labels are a Work-Sans-like sans (system default). A font helper
//  falls back to the system faces, so bundling the exact .ttf files later is a
//  drop-in with no code change.
//

import SwiftUI

enum Theme {

    // MARK: - Palette

    /// Warm cream — the "paper" background (Neutral #F2E8DF).
    static let cream = Color(hex: 0xF2E8DF)
    /// Slightly deeper cream for cards/fills on paper.
    static let creamSunken = Color(hex: 0xEADFD2)
    /// Terracotta — the primary accent (Primary #B35433).
    static let terracotta = Color(hex: 0xB35433)
    /// Warm charcoal — secondary / strong text on paper (#4A443F).
    static let charcoal = Color(hex: 0x2A2420)
    /// Muted warm grey for supporting body text on paper.
    static let stone = Color(hex: 0x8A8078)

    /// Warm near-black — the "stage" background behind the camera.
    static let ink = Color(hex: 0x1C1815)
    /// A touch lighter than ink, for stage panels and dividers.
    static let inkRaised = Color(hex: 0x2A2420)
    /// Rose-gold / copper — the accent used on stage (outlines, rings, numbers).
    static let copper = Color(hex: 0xC79A78)
    /// Muted cream for supporting text on stage.
    static let inkStone = Color(hex: 0x9A8E82)

    // MARK: - App chrome (kept for callers that still reference these names)

    static let background = ink
    static let accent = terracotta

    // MARK: - Overlay play colours (§13.5), retuned to the palette

    static let upcoming = copper          // approaching / fill
    static let hit = Color(hex: 0x4CAF50) // vibrant green for correct hit
    static let miss = Color(hex: 0x9E4B3A)// muted red-brown, still warm
    static let wrong = Color(hex: 0xC9A227)// amber, wrong key

    // MARK: - Overlay geometry

    static let keyOutlineWidth: CGFloat = 3
    static let keyCornerRadius: CGFloat = 6
    static let approachTrackHeight: CGFloat = 96
    /// Fraction from the left where the strike line sits on the approach track.
    static let strikeLineFraction: CGFloat = 0.15
    /// Seconds of lookahead shown on the approach track.
    static let approachLookaheadSeconds: Double = 3
}

// MARK: - Typography

extension Font {
    /// Caslon-like serif headline. Uses a bundled Libre Caslon Text face if
    /// present, else the system serif (New York) — visually very close.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if UIFont.fontNames(forFamilyName: "Libre Caslon Text").isEmpty {
            return .system(size: size, weight: weight, design: .serif)
        }
        let bold: Set<Font.Weight> = [.semibold, .bold, .heavy, .black]
        let name = bold.contains(weight) ? "LibreCaslonText-Bold" : "LibreCaslonText-Regular"
        return .custom(name, size: size)
    }

    /// Work-Sans-like sans for body and labels. Falls back to the system sans.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if UIFont.fontNames(forFamilyName: "Work Sans").isEmpty {
            return .system(size: size, weight: weight, design: .default)
        }
        return .custom("WorkSans-Regular", size: size).weight(weight)
    }
}

// MARK: - Reusable text treatments

extension View {
    /// The uppercase, letter-spaced label used for section headers and eyebrows.
    func eyebrow(_ color: Color) -> some View {
        self
            .font(.sans(12, weight: .semibold))
            .textCase(.uppercase)
            .tracking(2.5)
            .foregroundStyle(color)
    }
}

extension Text {
    /// Convenience for a tracked uppercase eyebrow string.
    func trackedLabel() -> some View {
        self.textCase(.uppercase).tracking(2.5)
    }
}

// MARK: - Hex

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

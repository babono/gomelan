//
//  AppControlSurface.swift
//  Kotek
//
//  The surface under every control: its height, padding, fill and hit area.
//

import SwiftUI

enum AppControlShape { case capsule, circle }

/// SOLID, since the November 2026 redesign, and TACTILE since the Nawa Sanga
/// design system: each control stands on a darker base a few points below
/// its face — Merah on Merah tua, white on Garis — and sinks onto it while
/// held, so it looks like something you can press before anyone presses it.
/// It was Liquid Glass, and glass is iOS-only while the app is going to
/// Android too; a fill and an edge are buildable on both. (What glass taught,
/// and still holds: the system button styles size a circle from its GLYPH, so
/// a chevron, a gear and a question mark come out three sizes. Here a circle
/// is `size.height` square whatever it holds.)
///
/// The base hangs BELOW the control's frame rather than inside it, so a
/// layout measured before the edge existed did not move; the footers' bottom
/// padding is what it hangs into. A compact control is drawn at 36 and
/// targeted at 44, the HIG minimum: someone reaching for it is standing over
/// an instrument holding a mallet.
struct AppControlSurface: ViewModifier {
    let size: AppButtonSize
    let shape: AppControlShape
    let prominence: AppButton.Prominence
    /// Replaces the primary's Merah, e.g. the Ireng of "Continue as guest",
    /// or the selected chip's Ireng (Kotek Studio's Polos red, Sangsih blue).
    var tint: Color?

    @Environment(\.isEnabled) private var isEnabled

    private var depth: CGFloat {
        size.depth
    }

    /// A disabled primary is its colours washed into the ground — opaque, so
    /// the face does not show its own base through it. (At 30% alpha it did.)
    private func washed(_ color: Color) -> Color {
        isEnabled ? color : color.mix(with: Theme.ground, by: 0.6)
    }

    private var fill: Color {
        switch prominence {
        case .primary: washed(tint ?? Theme.buttonFill)
        case .secondary: Theme.glassTint
        case .quiet: Theme.deep
        case .selected: tint ?? Theme.tertiary
        }
    }

    /// Only the outlined button has an outline; every other fill is its own
    /// edge.
    private var outline: Color {
        prominence == .secondary ? Theme.hairline : .clear
    }

    /// What it stands on. The flat looks stand on nothing: a quiet control
    /// should not look pressable before the way on does, and a selected one
    /// is already "in" — it sits sunk, where a pressed face lands (`sunk`).
    private var base: Color? {
        switch prominence {
        case .primary: washed(tint.map { $0.mix(with: .black, by: 0.3) } ?? Theme.buttonBase)
        case .secondary: Theme.hairline
        case .quiet, .selected: nil
        }
    }

    private var sunk: Bool {
        prominence == .selected
    }

    func body(content: Content) -> some View {
        switch shape {
        case .capsule:
            content
                .padding(.horizontal, size.horizontalPadding)
                .frame(minHeight: size.height)
                .tactile(Capsule(), fill: fill, outline: outline, base: base, depth: depth, sunk: sunk)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Capsule())
        case .circle:
            content
                .frame(width: size.height, height: size.height)
                .tactile(Circle(), fill: fill, outline: outline, base: base, depth: depth, sunk: sunk)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
    }
}

/// A face on a base: the one tactile look, for the controls above and for
/// the cards that are pressed like them (a gangsa, a kotekan). It sinks while
/// the button it labels is held — see `controlPressed`.
struct Tactile<S: InsettableShape>: ViewModifier {
    let shape: S
    let fill: Color
    var outline: Color = .clear
    var outlineWidth: CGFloat = 1
    /// nil: flat, no edge, no sink.
    var base: Color?
    var depth: CGFloat
    /// Held down for good: the face sits `depth` lower, where a pressed
    /// control's face lands — a selected chip reads as one pressed and left
    /// pressed, its bottom level with its neighbours' edges.
    var sunk = false

    @Environment(\.controlPressed) private var pressed

    func body(content: Content) -> some View {
        let sink = sunk || (pressed && base != nil) ? depth : 0
        content
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(outline, lineWidth: outlineWidth))
            .offset(y: sink)
            // Becoming sunk never animates: the tap that selects it has
            // already pressed the face down, so it should simply stay there.
            // Animated (by the switcher's own animation), the release lifted
            // it for a frame and it then slid back down in its new colour.
            // Coming back up when another is chosen does animate.
            .animation(sunk ? nil : .easeOut(duration: 0.12), value: sunk)
            // Behind the face, in the face's resting frame, `depth` lower.
            .background {
                if let base {
                    shape.fill(base).offset(y: depth)
                }
            }
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

extension View {
    func tactile(
        _ shape: some InsettableShape,
        fill: Color,
        outline: Color = .clear,
        outlineWidth: CGFloat = 1,
        base: Color?,
        depth: CGFloat,
        sunk: Bool = false
    ) -> some View {
        modifier(Tactile(
            shape: shape, fill: fill, outline: outline, outlineWidth: outlineWidth,
            base: base, depth: depth, sunk: sunk
        ))
    }
}

extension View {
    func appControlSurface(
        size: AppButtonSize,
        shape: AppControlShape,
        prominence: AppButton.Prominence,
        tint: Color? = nil
    ) -> some View {
        modifier(AppControlSurface(
            size: size, shape: shape, prominence: prominence, tint: tint
        ))
    }
}

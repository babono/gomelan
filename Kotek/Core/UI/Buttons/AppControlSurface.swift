//
//  AppControlSurface.swift
//  Kotek
//
//  The glass under every control: its height, padding, tint and hit area.
//

import SwiftUI

enum AppControlShape { case capsule, circle }

/// Drawn here rather than by the system's `.glass` / `.glassProminent` button
/// styles, for two reasons found the hard way:
/// - `.buttonStyle(.glass).tint(...)` does not tint the glass — only the text —
///   so the ground colour never showed. `glassEffect(.regular.tint(...))` does.
/// - `.buttonBorderShape(.circle)` sizes the circle from the GLYPH, so a back
///   chevron, a gear and a question mark came out three different sizes.
///   Here a circle is `size.height` square whatever it holds.
///
/// Secondary glass is tinted with the ground, so it reads as a raised piece of
/// the background; the primary is tinted gold. A 36pt compact control is drawn
/// at 36 and targeted at 44, which is the HIG minimum: someone reaching for it
/// is standing over an instrument holding a mallet.
struct AppControlSurface: ViewModifier {
    let size: AppButtonSize
    let shape: AppControlShape
    let prominence: AppButton.Prominence
    /// Replaces the primary's gold, e.g. the red of a record button.
    var tint: Color?
    /// Grow the touch target to 44pt round a smaller drawn control. Off for a
    /// `Menu` label: a menu stretches its glass to the label's whole frame, so
    /// the target growth was drawn — a 44pt menu beside 36pt switcher segments.
    var growsHitArea = true

    @Environment(\.isEnabled) private var isEnabled

    private var glass: Glass {
        // A disabled primary is a faint gold wash, not the way-on at 40%
        // opacity: that left gold glass with dim type that nobody could read.
        if prominence == .primary, !isEnabled {
            return .regular.tint((tint ?? Theme.buttonFill).opacity(0.18))
        }
        let color = prominence == .primary ? tint ?? Theme.buttonFill : Theme.glassTint
        return .regular.tint(color).interactive(isEnabled)
    }

    func body(content: Content) -> some View {
        switch shape {
        case .capsule:
            content
                .padding(.horizontal, size.horizontalPadding)
                .frame(minHeight: size.height)
                .glassEffect(glass, in: Capsule())
                .frame(minWidth: growsHitArea ? 44 : nil, minHeight: growsHitArea ? 44 : nil)
                .contentShape(Capsule())
        case .circle:
            content
                .frame(width: size.height, height: size.height)
                .glassEffect(glass, in: Circle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
    }
}

extension View {
    func appControlSurface(
        size: AppButtonSize,
        shape: AppControlShape,
        prominence: AppButton.Prominence,
        tint: Color? = nil,
        growsHitArea: Bool = true
    ) -> some View {
        modifier(AppControlSurface(
            size: size, shape: shape, prominence: prominence, tint: tint, growsHitArea: growsHitArea
        ))
    }
}

//
//  AppButtonStyle.swift
//  Kotek
//
//  The tick under every control in the app.
//

import SwiftUI

/// Every button in the app strikes a kajar when you press it.
///
/// A `PrimitiveButtonStyle` rather than a wrapper view or a call added to each
/// action, because it is the only thing that sits between the tap and the
/// action WITHOUT the call sites having to remember: a button gets the tick by
/// being a button. There are fifty-odd of them across the flow screens and the
/// dev screens, and one of them being silent reads as a bug.
///
/// It draws nothing inside but the press: the surface is the label's own
/// (`AppControlSurface`), because a system button style would apply inside
/// this one and win over anything we put on it. The press goes down to that
/// surface as `controlPressed`, so a tactile control can sink onto its base
/// (it was `.plain`, whose press is a dim the redesign has no use for). `AppButton` / `AppIconButton` are the
/// controls; use `.appPlain` directly for what you tap that is not one: cards,
/// grid cells, dots.
///
/// A disabled button never triggers, so it never ticks. That falls out of
/// `.disabled()` being applied outside the style, and is the behaviour we want:
/// the stepper at its limit should feel like nothing happened, because nothing did.
struct AppButtonStyle: PrimitiveButtonStyle {
    /// False for a button whose own sound must not be spoiled by a tick, e.g.
    /// one that starts the mic or plays a recording back.
    var ticks = true

    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            if ticks { KajarTick.strike() }
            configuration.trigger()
        } label: {
            configuration.label
        }
        .buttonStyle(PressReporting())
    }
}

extension EnvironmentValues {
    /// True while the button this view labels is held down — read by
    /// `AppControlSurface` and the tactile cards to sink onto their base.
    @Entry var controlPressed = false
}

/// `.plain` without the dim, passing the press down instead.
private struct PressReporting: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.controlPressed, configuration.isPressed)
    }
}

extension PrimitiveButtonStyle where Self == AppButtonStyle {
    /// `.buttonStyle(.appPlain)` — the app's `.plain`, with the tick.
    static var appPlain: AppButtonStyle {
        AppButtonStyle()
    }
}

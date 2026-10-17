//
//  Kajar.swift
//  Kotek
//
//  The tick under every control: a kajar struck when you press a button or flip
//  a switch.
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
/// It re-applies `.plain` inside, so the look and the press dimming are exactly
/// what they were — this style replaced `.buttonStyle(.plain)` throughout, and
/// adds a sound and nothing else.
///
/// A disabled button never triggers, so it never ticks. That falls out of
/// `.disabled()` being applied outside the style, and is the behaviour we want:
/// the stepper at its limit should feel like nothing happened, because nothing did.
struct KajarButtonStyle: PrimitiveButtonStyle {
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
        .buttonStyle(.plain)
    }
}

extension PrimitiveButtonStyle where Self == KajarButtonStyle {
    /// `.buttonStyle(.kajar)` — the app's `.plain`.
    static var kajar: KajarButtonStyle {
        KajarButtonStyle()
    }
}

/// Every switch in the app ticks when it flips.
///
/// Set ONCE, on the root — unlike `.kajar` on buttons, which has to be written
/// at each call site because every button in this codebase already names
/// `.plain` and an explicit style beats an inherited one. Nothing sets a toggle
/// style, so the environment carries this everywhere by itself.
///
/// Renders `.switch` inside, which is what these were getting from the default
/// on iOS anyway.
struct KajarToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(isOn: configuration.$isOn) { configuration.label }
            .toggleStyle(.switch)
            // On the VALUE, not on the touch: a switch can also be flipped by a
            // drag across it, and that should sound the same as tapping it.
            .onChange(of: configuration.isOn) {
                KajarTick.strike()
            }
    }
}

extension ToggleStyle where Self == KajarToggleStyle {
    static var kajar: KajarToggleStyle {
        KajarToggleStyle()
    }
}

extension View {
    /// Strike the tick whenever `value` changes.
    ///
    /// For the controls that are not buttons and give no press to hook — a
    /// `Toggle`, a segmented `Picker`, a `Menu` selection. Driven by the value
    /// rather than by the touch on purpose: these are the controls where the
    /// tap and the change are not the same event, and the change is the one the
    /// player is listening for.
    ///
    /// Deliberately NOT used on the sliders. A slider changes continuously, and
    /// a kajar per step is a machine gun.
    func kajarOnChange(of value: some Equatable) -> some View {
        onChange(of: value) {
            KajarTick.strike()
        }
    }
}

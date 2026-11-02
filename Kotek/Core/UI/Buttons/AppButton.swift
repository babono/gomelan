//
//  AppButton.swift
//  Kotek
//
//  The labelled button: GO, NEXT, CALIBRATE, Cancel, Delete, a utility in a card.
//

import SwiftUI

struct AppButton: View {
    /// The design system's four looks:
    /// - `primary`: the screen's way on — Merah (or its `tint`) on a Merah tua
    ///   edge, white type. One per screen.
    /// - `secondary`: every other button — white, outlined and edged in Garis
    ///   ("Retry", back).
    /// - `quiet`: Krem, flat — a stepper's −/+, a tool not in use.
    /// - `selected`: Ireng, flat, white type — the chip or tool that is on.
    enum Prominence {
        case primary, secondary, quiet, selected

        /// A disabled control fades its type, not the whole button.
        func labelColor(tint: Color?, enabled: Bool) -> Color {
            switch self {
            // White on any fill: Merah, Ireng, a tint.
            case .primary, .selected: Theme.onButtonFill.opacity(enabled ? 1 : 0.75)
            case .secondary, .quiet: (tint ?? Theme.cream).opacity(enabled ? 1 : 0.4)
            }
        }
    }

    let title: LocalizedStringKey
    var systemImage: String?
    /// An icon AFTER the label. For the buttons that carry you forward through
    /// a flow — a leading icon labels what a button is, a trailing arrow says
    /// where it goes, and those are different jobs on the same control.
    var trailingSystemImage: String?
    var prominence = Prominence.secondary
    var size = AppButtonSize.regular
    /// Secondary: the label's colour (Delete in red). Primary: the fill's own
    /// colour (Record in red).
    var tint: Color?
    /// `.destructive` so VoiceOver says so; the look is the caller's `tint`.
    var role: ButtonRole?
    var fullWidth = false
    /// No kajar tick on press, for buttons that record or play audio.
    var silent = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: size == .compact ? 8 : 10) {
                if let systemImage {
                    // Symbol metrics, not text metrics — see `Font.symbol`.
                    Image(systemName: systemImage)
                        .font(.symbol(size.symbolPoints, weight: .semibold))
                }
                Text(title).appLabel(size, prominence: prominence)
                if let trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .font(.symbol(size.symbolPoints, weight: .semibold))
                }
            }
            .foregroundStyle(prominence.labelColor(tint: tint, enabled: isEnabled))
            // On the label, inside the button: outside it the surface would hug
            // the content instead of stretching.
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .appControlSurface(
                size: size,
                shape: .capsule,
                prominence: prominence,
                tint: prominence == .primary ? tint : nil
            )
        }
        .buttonStyle(AppButtonStyle(ticks: !silent))
    }
}

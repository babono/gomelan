//
//  AppButton.swift
//  Kotek
//
//  The labelled button: GO, NEXT, CALIBRATE, Cancel, Delete, a utility in a card.
//

import SwiftUI

struct AppButton: View {
    /// `primary` is the screen's way on, in gold-tinted glass and the loud
    /// label; `secondary` is every other button, in glass tinted with the
    /// ground and the plain one.
    enum Prominence {
        case primary, secondary

        /// Dark type on the gold: cream was tried at a lighter tint and
        /// disappeared into the background showing through. A disabled control
        /// fades its type rather than the whole button going to 40% opacity,
        /// which left a muddy glass with its label at 2:1.
        func labelColor(tint: Color?, enabled: Bool) -> Color {
            guard enabled else { return Theme.cream.opacity(self == .primary ? 0.6 : 0.4) }
            switch self {
            case .primary: return tint == nil ? Theme.onGlassFill : Theme.cream
            case .secondary: return tint ?? Theme.cream
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
    /// Secondary: the label's colour (Delete in red). Primary: the glass's own
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
            // On the label, inside the button: outside it the glass would hug
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

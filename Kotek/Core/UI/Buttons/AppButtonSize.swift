//
//  AppButtonSize.swift
//  Kotek
//
//  The one size scale for every labelled control, so no call site picks a
//  height, a padding or a font of its own.
//

import SwiftUI

/// One size per bar: every control in a bar — labelled, icon-only and the
/// primary alike — takes the same size. Flow-screen footers and headers are
/// `.regular`; the compact strips over the camera feed are `.compact`; `.large`
/// is for a lone hero button, never a bar that holds other controls.
enum AppButtonSize {
    /// Top-bar chips, dialog buttons, utilities inside a card.
    case compact
    /// Everything in a normal bar, and every standard icon-only circle.
    case regular
    /// The screen's way on: GO, NEXT, START.
    case large

    /// The height of the drawn glass. A compact control is drawn at 36 but
    /// still takes a 44pt target — see `AppControlSurface`.
    var height: CGFloat {
        switch self {
        case .compact: 36
        case .regular: 44
        case .large: 52 // = Theme.buttonHeight, so Sign in with Apple sits level
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: 16
        case .regular: 22
        case .large: 28
        }
    }

    var labelPoints: CGFloat {
        switch self {
        case .compact: 14
        case .regular: 16
        case .large: 19
        }
    }

    var symbolPoints: CGFloat {
        switch self {
        case .compact: 14
        case .regular: 16
        case .large: 18
        }
    }
}

extension View {
    /// How every label in a control is set.
    ///
    /// The primary is the loud one: heavy, tracked, uppercase. Uppercase +
    /// tracking makes even a short word wide, and in a narrow column SwiftUI
    /// will happily break "Listening…" across two lines and blow out the
    /// control's height rather than let it overflow, so no label wraps —
    /// whoever adds a long one sees it clipped, which reads as "shorten this",
    /// not as a broken control. The tracking is what keeps a short, very heavy
    /// word from setting solid.
    ///
    /// Everything else is the plain semibold sentence-case face the secondary
    /// buttons always had: one primary per screen is what makes it the way on.
    @ViewBuilder
    func appLabel(_ size: AppButtonSize, prominence: AppButton.Prominence = .secondary) -> some View {
        switch prominence {
        case .primary:
            textCase(.uppercase)
                .tracking(Theme.buttonTracking)
                .font(.sans(size.labelPoints, weight: Theme.buttonWeight))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        case .secondary:
            font(.sans(size.labelPoints, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

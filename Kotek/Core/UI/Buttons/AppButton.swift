//
//  AppButton.swift
//  Kotek
//
//  The labelled button — the only one. It replaced PillButton, CapsuleButton,
//  PrimaryButton, SecondaryButton and RealignButton, which drew the same
//  capsule four ways with different type, heights and surfaces.
//
//  A call site chooses WHAT it says and how loudly (`prominence`); the type,
//  height, padding and surface are the component's. Two voices, on purpose:
//   - `.primary`: the brand voice — tracked, Black, UPPERCASE — on gold glass.
//   - everything else: SF Semibold 16, sentence case, on flat glass.
//
//  The icon goes BEFORE the label when it says what the button is (Create, Add,
//  Edit) and AFTER when it says where it goes (Next →). Leading is the default.
//

import SwiftUI

enum ButtonScale {
    /// 44pt: the HIG minimum, and the height of every button but the main one.
    case regular
    /// 56pt: a screen's main call to action.
    case large

    var height: CGFloat {
        self == .large ? Theme.buttonHeight : Theme.tapTarget
    }
}

struct AppButton<Label: View>: View {
    var prominence: ControlProminence = .standard
    var size: ButtonScale = .regular
    var fullWidth = false
    /// No kajar tick on press, for buttons that record or play audio.
    var silent = false
    let action: () -> Void
    let label: Label

    @Environment(\.isEnabled) private var isEnabled

    init(
        prominence: ControlProminence = .standard,
        size: ButtonScale = .regular,
        fullWidth: Bool = false,
        silent: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.prominence = prominence
        self.size = size
        self.fullWidth = fullWidth
        self.silent = silent
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(role: prominence.role, action: action) {
            label
                .foregroundStyle(prominence == .primary && isEnabled ? Theme.onGlassFill : Theme.cream)
                .padding(.horizontal, prominence == .primary && size == .large ? 30 : prominence == .primary ? 18 : 24)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(minHeight: size.height)
                .controlSurface(prominence)
                .contentShape(Capsule())
        }
        .buttonStyle(KajarButtonStyle(ticks: !silent))
    }
}

extension AppButton where Label == AppButtonTitle {
    /// The usual button: a title, and optionally a symbol either side of it.
    init(
        _ title: String,
        systemImage: String? = nil,
        trailingSystemImage: String? = nil,
        prominence: ControlProminence = .standard,
        size: ButtonScale = .regular,
        fullWidth: Bool = false,
        silent: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            prominence: prominence,
            size: size,
            fullWidth: fullWidth,
            silent: silent,
            action: action
        ) {
            AppButtonTitle(
                title: title,
                systemImage: systemImage,
                trailingSystemImage: trailingSystemImage,
                prominence: prominence,
                size: size
            )
        }
    }
}

/// A button's words and symbols, set in the voice its prominence calls for.
struct AppButtonTitle: View {
    let title: String
    var systemImage: String?
    var trailingSystemImage: String?
    var prominence: ControlProminence
    var size: ButtonScale

    private var isPrimary: Bool {
        prominence == .primary
    }

    private var large: Bool {
        isPrimary && size == .large
    }

    var body: some View {
        HStack(spacing: large ? 10 : isPrimary ? 8 : 10) {
            if let systemImage {
                // Symbol metrics, not text metrics — see `Font.symbol`.
                Image(systemName: systemImage)
                    .font(.symbol(large ? 18 : isPrimary ? 14 : 16, weight: .semibold))
            }
            Text(title)
                .textCase(isPrimary ? .uppercase : nil)
                .tracking(isPrimary ? Theme.buttonTracking : 0)
                // SF has real weights, unlike the face this used to be, so a
                // button label can simply BE the weight it wants.
                .font(isPrimary ? .sans(large ? 19 : 14, weight: Theme.buttonWeight) : .sans(16, weight: .semibold))
            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(.symbol(large ? 16 : isPrimary ? 13 : 16, weight: .semibold))
            }
        }
        // A button label never wraps. Uppercase + tracking makes even a short
        // word wide, and in a narrow column SwiftUI will happily break
        // "Listening…" across two lines and blow out the height rather than
        // let it overflow. Whoever adds a long label sees it clipped — which
        // reads as "shorten this", not as a broken control.
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

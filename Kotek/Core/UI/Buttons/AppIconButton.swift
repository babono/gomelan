//
//  AppIconButton.swift
//  Kotek
//
//  The round button holding one symbol — back, settings, undo, stop. It
//  replaced CircleIconButton and the hand-built gears, pauses and trash cans
//  that each drew their own circle at their own size.
//
//  `label` is mandatory: a symbol alone tells VoiceOver nothing.
//

import SwiftUI

struct AppIconButton<Content: View>: View {
    let label: String
    var size: CGFloat = Theme.tapTarget
    var prominence: ControlProminence = .standard
    /// No kajar tick on press, for buttons that record or play audio.
    var silent = false
    let action: () -> Void
    let content: Content

    @Environment(\.isEnabled) private var isEnabled

    init(
        label: String,
        size: CGFloat = Theme.tapTarget,
        prominence: ControlProminence = .standard,
        silent: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.size = size
        self.prominence = prominence
        self.silent = silent
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(role: prominence.role, action: action) {
            content
                .font(.symbol(size * 17 / 44, weight: .semibold))
                .foregroundStyle(prominence == .primary && isEnabled ? Theme.onGlassFill : Theme.cream)
                .frame(width: size, height: size)
                .controlSurface(prominence, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(KajarButtonStyle(ticks: !silent))
        .accessibilityLabel(label)
    }
}

extension AppIconButton where Content == Image {
    init(
        systemImage: String,
        label: String,
        size: CGFloat = Theme.tapTarget,
        prominence: ControlProminence = .standard,
        silent: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(label: label, size: size, prominence: prominence, silent: silent, action: action) {
            Image(systemName: systemImage)
        }
    }
}

//
//  ControllerStatusChip.swift
//  Kotek
//
//  Whether the active gangsa's strike controller is with us (Flow E step 5),
//  next to the gangsa's name — the app cannot see which gangsa the controller
//  is clipped onto, so the name is how the player catches it being the wrong
//  one. When the plugged-in sensors no longer match the setup it becomes the
//  re-check prompt (§3.6.3).
//
//  Shared by the kotekan picker, Play and Settings. Draws nothing for a gangsa
//  without a controller.
//

import SwiftUI

struct ControllerStatusChip: View {
    @Environment(AppState.self) private var app
    /// Just the dot and a word — the practice screen's top bar.
    var compact = false

    var body: some View {
        if let link = app.profile.controller {
            if app.controllerNeedsCheck, !compact {
                Button {
                    app.openControllerSetup(recheck: true, returnTo: app.screen)
                } label: {
                    chip(
                        color: Theme.wrong,
                        text: String(localized: "Sensors changed on \(app.profile.name) · Check them")
                    )
                }
                .buttonStyle(.appPlain)
            } else {
                chip(color: color, text: compact ? shortText : "\(app.profile.name) · \(longText(link))")
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private func chip(color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.sans(12, weight: .semibold))
                .foregroundStyle(Theme.cream.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: compact ? 34 : 30)
        .background(.black.opacity(0.3), in: Capsule())
    }

    private var color: Color {
        if app.controllerConnected { return Theme.hit }
        if case .unavailable = app.sensor.status { return Theme.miss }
        return Theme.gold
    }

    private var shortText: String {
        app.controllerConnected ? String(localized: "Sensors") : String(localized: "Not scoring")
    }

    private func longText(_ link: ControllerLink) -> String {
        if app.controllerConnected { return String(localized: "\(link.name) connected") }
        if case let .unavailable(why) = app.sensor.status { return why }
        return String(localized: "Looking for \(link.name)… not scoring yet")
    }
}

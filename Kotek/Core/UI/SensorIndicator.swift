//
//  SensorIndicator.swift
//  Kotek
//
//  Icon-only: is the strike controller with us, and so will a session be
//  scored? Sits beside the settings gear on the kotekan picker. The glyph says
//  it at a glance — slashed is "no sensor, guidance only", lit is "scored" —
//  and tapping it says it in words, because a custom icon with no label is
//  something a player can only learn by being told.
//
//  It is also the re-check prompt (§3.6.3) when the plugged-in sensors no
//  longer match the setup, which the text chip used to be on this screen.
//

import SwiftUI

struct SensorIndicator: View {
    @Environment(AppState.self) private var app
    @State private var showing = false

    var body: some View {
        AppIconButton(label: label, action: { showing = true }) {
            // The art is 2:1; template-rendered, so the colour tints it. Always
            // cream, like the gear: the slash says connected or not, and colour
            // on a header control is kept for what needs the player to act.
            Image(app.controllerConnected ? "sensor" : "sensor-disabled")
                .resizable()
                .scaledToFit()
                .frame(width: 22)
        }
        .overlay(alignment: .topTrailing) {
            if app.controllerNeedsCheck {
                Circle()
                    .fill(Theme.wrong)
                    .frame(width: 9, height: 9)
                    .offset(x: -3, y: 3)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHint("Shows what this means")
        // Compact height (a landscape iPhone) would turn this into a sheet.
        .popover(isPresented: $showing) {
            explanation
                .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: - Words

    private var controllerName: String? {
        app.profile.controller?.name
    }

    private var label: String {
        if app.controllerNeedsCheck { return "Sensors changed, check keys" }
        return app.controllerConnected ? "Sensor connected, scoring on" : "No sensor, guidance only"
    }

    private var headline: String {
        if app.controllerNeedsCheck { return "Sensors changed" }
        if app.controllerConnected { return "Sensor connected" }
        return controllerName.map { "Looking for \($0)" } ?? "No sensor"
    }

    private var detail: String {
        if app.controllerNeedsCheck {
            return "The plugged-in sensors don't match the setup. Check the keys."
        }
        if app.controllerConnected { return "\(controllerName ?? "The sensor") is scoring this session." }
        if controllerName != nil { return "Guidance only until it connects." }
        return "Guidance only. Set up a sensor to be scored."
    }

    /// Setup is only the fix when it is up to the player: a controller that
    /// is set up but out of range just needs to be switched on.
    private var actionTitle: String? {
        if app.controllerNeedsCheck { return "Check keys" }
        return app.profile.controller == nil && !app.controllerConnected ? "Set up sensor" : nil
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headline)
                .font(.sans(15, weight: .semibold))
            Text(detail)
                .font(.sans(13))
                .foregroundStyle(.secondary)
            if let actionTitle {
                AppButton(actionTitle, prominence: .primary) {
                    showing = false
                    app.openControllerSetup(recheck: app.controllerNeedsCheck, returnTo: app.screen)
                }
                .padding(.top, 6)
            }
        }
        .padding(16)
        .frame(minWidth: 220, alignment: .leading)
    }
}

//
//  SensorIndicator.swift
//  Kotek
//
//  Icon-only: is the strike controller with us, and so will a session be
//  scored? Sits beside the settings gear on the kotekan picker. Waves lit is
//  "scored", waves pulsing is "looking for it", the crossed-out art is "no
//  sensor, guidance only".
//
//  Not a button, on purpose: it only reports. Setting the sensor up or
//  re-checking its keys lives in Settings → Strike controller, which is
//  where the §3.6.3 re-check prompt goes too. A dot on the glyph says the
//  plugged-in sensors no longer match the setup.
//

import SwiftUI

struct SensorIndicator: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // `sensor.radiowaves.left.and.right` is the live glyph: it scales and
        // weighs like the gear beside it, at the same 17pt as the glyph inside
        // the gear's 44pt circle (`AppIconButton`). SF Symbols has no slashed
        // version of it, so "no sensor" is the drawn `sensor-disabled` art — the
        // same 2:1 shape, sized to the symbol's width.
        glyph
            .foregroundStyle(Theme.cream)
            .frame(height: 44)
            .overlay(alignment: .topTrailing) {
                if app.controllerNeedsCheck {
                    Circle()
                        .fill(Theme.wrong)
                        .frame(width: 9, height: 9)
                        .offset(x: 3, y: 9)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(label)
    }

    @ViewBuilder
    private var glyph: some View {
        if connected || looking {
            Image(systemName: "sensor.radiowaves.left.and.right")
                .font(.symbol(17, weight: .semibold))
                .symbolEffect(.pulse, isActive: looking && !reduceMotion)
        } else {
            Image("sensor-disabled")
                .resizable()
                .scaledToFit()
                .frame(width: 32)
        }
    }

    private var connected: Bool {
        app.controllerConnected
    }

    /// A controller is set up and Bluetooth is hunting for it.
    private var looking: Bool {
        guard !connected, app.profile.controller != nil else { return false }
        return app.sensor.status == .scanning || app.sensor.status == .connecting
    }

    private var label: String {
        if app.controllerNeedsCheck { return "Sensors changed, check keys in Settings" }
        if connected { return "Sensor connected, scoring on" }
        return looking ? "Looking for sensor" : "No sensor, guidance only"
    }
}

//
//  SensorIndicator.swift
//  Kotek
//
//  Is the strike controller with us, and so will a session be scored? Said
//  as a status row in the pickers' ⋯ menu (`TopBar.showsMenu`). It was an
//  icon of its own beside the gear (waves lit, pulsing, or the crossed-out
//  `sensor-disabled` art); folded into the menu, the wording is the same and
//  the top bar has one glyph fewer.
//
//  Not an action, on purpose: it only reports. Setting the sensor up or
//  re-checking its keys lives in Settings → Strike controller, which is
//  where the §3.6.3 re-check prompt goes too. A dot on the ⋯ says the
//  plugged-in sensors no longer match the setup.
//

import SwiftUI

enum SensorIndicator {
    /// The state in words and the same glyphs the indicator always drew:
    /// `sensor.radiowaves.left.and.right` while it is with us or being looked
    /// for, the drawn `sensor-disabled` art when there is none (SF Symbols has
    /// no slashed version of it).
    static func summary(for app: AppState) -> (text: String, icon: Image) {
        let live = Image(systemName: "sensor.radiowaves.left.and.right")
        if app.controllerNeedsCheck { return (String(localized: "Sensors changed · check in Settings"), live) }
        if app.controllerConnected { return (String(localized: "Sensor connected · scoring"), live) }
        return looking(app)
            ? (String(localized: "Looking for sensor"), live)
            : (String(localized: "No sensor · not scoring"), Image("sensor-disabled").renderingMode(.template))
    }

    /// A controller is set up and Bluetooth is hunting for it.
    private static func looking(_ app: AppState) -> Bool {
        guard !app.controllerConnected, app.profile.controller != nil else { return false }
        return app.sensor.status == .scanning || app.sensor.status == .connecting
    }
}

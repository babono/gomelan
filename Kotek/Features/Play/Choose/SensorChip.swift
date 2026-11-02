//
//  SensorChip.swift
//  Kotek
//
//  Whether this session will be scored, said where you choose the pattern
//  rather than one level down in the ⋯ menu. The menu row only reported;
//  with no sensor the chip also says what that costs and offers the way to
//  fix it, so "why is there no score?" is answered before you start.
//

import SwiftUI

struct SensorChip: View {
    @Environment(AppState.self) private var app
    @State private var explaining = false

    private enum Status { case on, check, looking, none }

    private var state: Status {
        if app.controllerNeedsCheck { return .check }
        if app.controllerConnected { return .on }
        if app.profile.controller != nil,
           app.sensor.status == .scanning || app.sensor.status == .connecting { return .looking }
        return .none
    }

    var body: some View {
        Button {
            switch state {
            case .none: explaining = true
            case .check: app.openControllerSetup(recheck: true, returnTo: .chooseKotekan)
            case .on, .looking: break
            }
        } label: {
            HStack(spacing: 6) {
                icon.font(.symbol(12, weight: .semibold))
                Text(title).font(.sans(13, weight: .medium))
            }
            .foregroundStyle(state == .check ? Theme.wrong : Theme.cream.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .overlay(Capsule().strokeBorder(Theme.cream.opacity(0.25), lineWidth: 1))
            // The chip is drawn small; the target stays the HIG's 44.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.appPlain)
        .popover(isPresented: $explaining) { noSensor }
    }

    private var title: LocalizedStringKey {
        switch state {
        case .on: "Sensor on"
        case .check: "Check sensors"
        case .looking: "Looking for sensor…"
        case .none: "No sensor"
        }
    }

    @ViewBuilder
    private var icon: some View {
        if state == .none {
            Image("sensor-disabled").renderingMode(.template).resizable().scaledToFit().frame(width: 14, height: 14)
        } else {
            Image(systemName: "sensor.radiowaves.left.and.right")
        }
    }

    private var noSensor: some View {
        SensorTip(
            title: "No sensor found",
            message: "You can still play along, but your hits won't be scored.",
            onConnect: { app.openControllerSetup(returnTo: .chooseKotekan) },
            onDismiss: { explaining = false }
        )
    }
}

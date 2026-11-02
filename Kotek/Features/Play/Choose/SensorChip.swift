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
            // The design system's sensor chips: white and outlined, the
            // icon saying the state in Nawa Sanga — Pandan on, gold looking,
            // grey none — and the words dimming with it.
            HStack(spacing: 6) {
                icon.font(.symbol(12, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title).font(.sans(13, weight: .medium))
            }
            .foregroundStyle(state == .check ? Theme.destructive : state == .none ? Theme.description : Theme.cream)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline.opacity(0.6), lineWidth: 1))
            // The chip is drawn small; the target stays the HIG's 44.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.appPlain)
        .popover(isPresented: $explaining) { noSensor.presentationCompactAdaptation(.popover) }
    }

    private var title: LocalizedStringKey {
        switch state {
        case .on: "Sensor on"
        case .check: "Check sensors"
        case .looking: "Looking for sensor…"
        case .none: "No sensor"
        }
    }

    private var iconColor: Color {
        switch state {
        case .on: Theme.ok
        case .looking: Theme.pending
        case .check: Theme.destructive
        case .none: Theme.description
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
        VStack(alignment: .leading, spacing: 8) {
            Text("No sensor found")
                .font(.sans(17, weight: .semibold))
                .foregroundStyle(Theme.cream)
            Text("You can still play along, but your hits won't be scored.")
                .font(.sans(14))
                .foregroundStyle(Theme.cream.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                AppButton(title: "Connect", prominence: .primary, size: .compact) {
                    explaining = false
                    app.openControllerSetup(returnTo: .chooseKotekan)
                }
                AppButton(title: "Not now", size: .compact) { explaining = false }
            }
            .padding(.top, 6)
        }
        .padding(20)
        .frame(width: 320, alignment: .leading)
        .background(Theme.ground)
    }
}

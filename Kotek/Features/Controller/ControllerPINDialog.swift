//
//  ControllerPINDialog.swift
//  Kotek
//
//  The controller's 4-digit PIN (`GangsaSensor`'s AUTH): asked for when a
//  controller is locked to this phone — from RootView, since any screen that
//  follows a controller can meet one — and set or changed from the setup
//  screen's summary. Same panel as `ConfirmDialog`.
//

import SwiftUI

struct ControllerPINDialog: View {
    enum Mode {
        case unlock, protect, change
    }

    let mode: Mode
    let controllerName: String
    let sensor: GangsaSensor
    /// Cancel — and, setting or changing, done.
    let onClose: () -> Void

    @State private var pin = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.serif(24))
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(Theme.cream)

                Text(message)
                    .font(.sans(14))
                    .foregroundStyle(Theme.cream.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 16) {
                    field
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focused)
                        .foregroundStyle(Theme.cream)
                        .frame(width: 120)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Theme.ground, in: RoundedRectangle(cornerRadius: Theme.radius))
                    if sensor.isSendingPIN {
                        ProgressView().tint(Theme.gold)
                    } else if let error = sensor.pinError {
                        Text(error)
                            .font(.sans(14, weight: .semibold))
                            .foregroundStyle(Theme.wrong)
                    }
                }

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        Spacer(minLength: 0)
                        AppButton(title: mode == .unlock ? "Not now" : "Cancel", size: .compact, action: onClose)
                        AppButton(title: confirmTitle, prominence: .primary, size: .compact, action: submit)
                            .disabled(pin.count != 4 || sensor.isSendingPIN)
                    }
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .background(Theme.deep, in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Theme.cream.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
            .padding(.horizontal, 28)
            // Up top: landscape, the number pad takes the bottom half.
            .padding(.top, 16)
        }
        .onAppear { focused = true }
        .onChange(of: pin) { _, typed in
            let digits = String(typed.filter(\.isNumber).prefix(4))
            if digits != typed { pin = digits }
        }
        // A wrong PIN is cleared for the next try.
        .onChange(of: sensor.pinError) { _, error in
            if error != nil { pin = "" }
        }
        .onChange(of: sensor.isSendingPIN) { was, sending in
            // Unlocking closes itself: the controller stops being locked.
            if mode != .unlock, was, !sending, sensor.pinError == nil { onClose() }
        }
    }

    /// Hidden when it's someone else's PIN; shown when it's yours to choose,
    /// so a typo isn't what the controller ends up locked with.
    @ViewBuilder
    private var field: some View {
        if mode == .unlock {
            SecureField("····", text: $pin)
        } else {
            TextField("0000", text: $pin)
        }
    }

    private var title: String {
        switch mode {
        case .unlock: "Enter PIN"
        case .protect: "Set a PIN"
        case .change: "Change PIN"
        }
    }

    private var confirmTitle: String {
        mode == .unlock ? "Unlock" : "Save PIN"
    }

    private var message: String {
        switch mode {
        case .unlock:
            "\(controllerName) is protected. Ask its owner for the 4-digit PIN."
        case .protect:
            "Phones without it can't use \(controllerName). You become its owner, and only your Apple ID can change the PIN. "
                + "Forgot it? Open the enclosure and hold BOOT for 10 seconds."
        case .change:
            "Other phones will be asked for the new PIN."
        }
    }

    private func submit() {
        guard pin.count == 4 else { return }
        switch mode {
        case .unlock: sensor.unlock(pin: pin)
        case .protect: sensor.protect(pin: pin)
        case .change: sensor.changePIN(to: pin)
        }
    }
}

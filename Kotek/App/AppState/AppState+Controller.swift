//
//  AppState+Controller.swift
//  Kotek
//
//  The strike controller (PRD §3.6): opening its setup, saving what the setup
//  learned onto the active gangsa, and which controller Bluetooth should be
//  following (Flow E).
//

import Foundation

extension AppState {
    // MARK: - Setup screen

    func openControllerSetup(recheck: Bool = false, returnTo: Route = .settings, offer: Bool = false) {
        controllerSetupRecheck = recheck
        controllerSetupReturn = returnTo
        controllerSetupIsOffer = offer
        screen = .controllerSetup
    }

    func closeControllerSetup() {
        screen = controllerSetupReturn
    }

    /// Flow D's Finish: the controller, and which input sits on each key, onto
    /// THIS gangsa only — other gangsa sharing the controller keep theirs.
    func saveControllerSetup(_ link: ControllerLink, inputForKey: [Int?]) {
        profile.controller = link
        for i in profile.keys.indices {
            profile.keys[i].sensorInput = i < inputForKey.count ? inputForKey[i] : nil
        }
        saveProfile()
        closeControllerSetup()
    }

    /// This gangsa only. The controller's own row stays on the server — it is
    /// still the player's, and other gangsa may use it.
    func forgetController() {
        profile.controller = nil
        for i in profile.keys.indices {
            profile.keys[i].sensorInput = nil
        }
        saveProfile()
    }

    // MARK: - Reconnect (Flow E)

    /// What Bluetooth should be doing for the screen on show. Nil where the
    /// screen drives the controller itself.
    var sensorTarget: GangsaSensor.Target? {
        switch screen {
        case .controllerSetup, .sensorTest:
            nil
        // The waterfall and Create Kotek's recording take any controller
        // themselves when the gangsa has none set up — the prototype wiring
        // both were built on.
        case .waterfall where profile.controller == nil,
             .createKotek where profile.controller == nil:
            nil
        default:
            profile.controller.map { .hardware($0.hardwareId) } ?? GangsaSensor.Target.none
        }
    }

    /// The active gangsa's controller is connected and ready.
    var controllerConnected: Bool {
        profile.controller.map { sensor.isConnected(to: $0.hardwareId) } ?? false
    }

    /// The sensors plugged in now are not the ones this gangsa was set up
    /// with, so its map cannot be trusted (§3.6.3). Plug-detect boards only —
    /// without it the controller cannot tell, and re-checking is manual.
    ///
    /// A gangsa set up before plug detect has no recorded set, which reads as
    /// different: the banner shows once and the re-check records it.
    var controllerNeedsCheck: Bool {
        guard controllerConnected, let link = profile.controller,
              let info = sensor.info, info.hasPlugDetect
        else { return false }
        return link.inputs.map(Set.init) != info.plugged
    }
}

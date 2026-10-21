//
//  Route.swift
//  Kotek
//
//  Created by Dimas Nugraha on 05/10/26.
//

import Foundation

enum Route: String, Hashable {
    case welcome
    case checkingPermissions
    case permissionsBlocked
    case profileSetup
    case chooseInstrument // Multi-instrument selection
    case choosingKeyCount // setup 1/2
    case framing // realign only — no longer part of adding a gangsa
    case aligning // realign only — no longer part of adding a gangsa
    case calibrating // setup 2/2 · baseline · learn the voice
    case baseline
    case chooseKotekan
    case createKotek
    case countdown
    case playing
    case results
    case settings
    case history
    case malletTest
    case detectionTest
    case audioTest
    case captureTraining
    case noteCapture
    case sensorTest
    case controllerSetup // strike controller · Flow D
    case waterfall // play without the camera: notes fall onto a drawn gangsa
    case coopSetup // one-screen coop: two players, their gangsa and halves
    case coopPlay // one-screen coop: both halves, side by side

    /// Screens whose ground is the live camera feed rather than the pattern.
    var isCameraScreen: Bool {
        switch self {
        case .framing, .aligning, .calibrating, .baseline,
             .countdown, .playing, .malletTest, .detectionTest, .audioTest,
             .captureTraining:
            true
        default:
            false
        }
    }
}

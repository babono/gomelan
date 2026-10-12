//
//  Route.swift
//  Kotek
//
//  Created by Dimas Nugraha on 05/10/26.
//

import AppIntents

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
    case sensorTest
    case controllerSetup // strike controller · Flow D
    case waterfall // play without the camera: notes fall onto a drawn gangsa

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

nonisolated extension Route: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation =
        "Screen Option"

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .welcome: "Welcome",
        .checkingPermissions: "Checking Permissions",
        .permissionsBlocked: "Permissions Blocked",
        .profileSetup: "Profile Setup",
        .chooseInstrument: "Choose Instrument",
        .choosingKeyCount: "Choosing Key Count",
        .framing: "Framing",
        .aligning: "Aligning",
        .calibrating: "Calibrating",
        .baseline: "Baseline",
        .chooseKotekan: "Choose Kotekan",
        .createKotek: "Create Kotek",
        .countdown: "Countdown",
        .playing: "Playing",
        .results: "Results",
        .settings: "Settings",
        .history: "Practice History",
        .malletTest: "Mallet Test",
        .detectionTest: "Detection Test",
        .audioTest: "Audio Test",
        .captureTraining: "Capture Training",
        .sensorTest: "Sensor Test",
        .controllerSetup: "Controller Setup",
        .waterfall: "Waterfall Practice",
    ]
}

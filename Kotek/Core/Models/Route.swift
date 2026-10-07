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
    case chooseInstrument // Multi-instrument selection
    case choosingKeyCount // setup 1/4
    case framing // setup 2/4
    case aligning // setup 3/4
    case calibrating // baseline · learn the voice
    case baseline
    case chooseKotekan
    case countdown
    case playing
    case results
    case settings
    case malletTest
    case detectionTest
    case audioTest
    case captureTraining
    case sensorTest

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
        .chooseInstrument: "Choose Instrument",
        .choosingKeyCount: "Choosing Key Count",
        .framing: "Framing",
        .aligning: "Aligning",
        .calibrating: "Calibrating",
        .baseline: "Baseline",
        .chooseKotekan: "Choose Kotekan",
        .countdown: "Countdown",
        .playing: "Playing",
        .results: "Results",
        .settings: "Settings",
        .malletTest: "Mallet Test",
        .detectionTest: "Detection Test",
        .audioTest: "Audio Test",
        .captureTraining: "Capture Training",
        .sensorTest: "Sensor Test",
    ]
}

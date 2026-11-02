//
//  Route.swift
//  Kotek
//
//  Created by Dimas Nugraha on 05/10/26.
//

import Foundation

enum Route: String, Hashable {
    case welcome
    case profileSetup
    case chooseInstrument // Multi-instrument selection
    case choosingKeyCount // setup 1/3
    case chooseKotekan
    case createKotek
    case results
    case settings
    case history
    case noteCapture // setup 2/3
    case sensorTest
    case controllerSetup // strike controller · Flow D
    case waterfall // play without the camera: notes fall onto a drawn gangsa
    case coopSetup // one-screen coop: two players, their gangsa and halves
    case coopPlay // one-screen coop: both halves, side by side
    case learn // a pattern taught in steps, before free play (`LearnStage`)

    // R The camera play mode went in November 2026, and with it ten routes:
    // R framing, aligning, calibrating and baseline (fitting the top-view
    // R camera and learning the gangsa's voice), countdown and playing (the
    // R overlay on the live feed), and the mallet, detection, audio and
    // R capture-training test screens — plus the permission gate that only
    // R the camera needed. `isCameraScreen` went with them.
}

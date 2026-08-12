//
//  RootView.swift
//  gomelan
//
//  Hosts the app state machine (PRD §13.4) and owns the shared capture/audio
//  services so they persist across screen transitions. Screens live on one of
//  two surfaces — warm "paper" (cream, light) or warm "stage" (ink, dark, behind
//  the camera) — and the background + colour scheme follow the current screen.
//

import SwiftUI

struct RootView: View {
    @State private var app = AppState()
    @State private var camera = CameraController()
    @State private var cue = CuePlayer()
    @State private var audio = AudioEngineController()

    var body: some View {
        ZStack {
            (isPaper ? Theme.cream : Theme.ink).ignoresSafeArea()
            content
        }
        .environment(app)
        .preferredColorScheme(isPaper ? .light : .dark)
        .statusBarHidden(true)
        .animation(.easeInOut(duration: 0.25), value: isPaper)
    }

    /// Cream, light screens vs. ink, dark camera/stage screens.
    private var isPaper: Bool {
        switch app.screen {
        case .welcome, .permissionsBlocked, .choosingKeyCount,
             .chooseInstrument, .chooseKotekan, .chooseHalf, .results, .settings:
            return true
        case .checkingPermissions, .framing, .aligning, .calibrating,
             .countdown, .playing, .malletTest, .detectionTest, .audioTest:
            return false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch app.screen {
        case .welcome:
            WelcomeView()
        case .checkingPermissions:
            PermissionsView(camera: camera)
        case .permissionsBlocked:
            PermissionsBlockedView()
        case .chooseInstrument:
            ChooseInstrumentView()
        case .choosingKeyCount:
            KeyCountView()
        case .framing:
            FramingView(camera: camera)
        case .aligning:
            AligningView(camera: camera)
        case .calibrating:
            CalibrationView(camera: camera, audio: audio)
        case .chooseKotekan:
            ChooseKotekanView()
        case .chooseHalf:
            ChooseHalfView()
        case .countdown, .playing:
            PlayView(camera: camera, audio: audio, cue: cue)
        case .results:
            ResultsView()
        case .settings:
            SettingsView()
        case .malletTest:
            MalletTestView(camera: camera)
        case .detectionTest:
            DetectionTestView(camera: camera, audio: audio)
        case .audioTest:
            AudioTestView(audio: audio)
        }
    }
}

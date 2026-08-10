//
//  RootView.swift
//  gomelan
//
//  Hosts the app state machine (PRD §13.4) and owns the shared capture/audio
//  services so they persist across screen transitions.
//

import SwiftUI

struct RootView: View {
    @State private var app = AppState()
    @State private var camera = CameraController()
    @State private var cue = CuePlayer()
    @State private var audio = AudioEngineController()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
        .environment(app)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
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
        case .framing:
            FramingView(camera: camera)
        case .choosingKeyCount:
            KeyCountView(camera: camera)
        case .aligning:
            AligningView(camera: camera)
        case .songList:
            SongListView()
        case .songDetail:
            SongDetailView()
        case .countdown, .playing:
            PlayView(camera: camera, audio: audio, cue: cue)
        case .results:
            ResultsView()
        case .settings:
            SettingsView()
        case .calibrating:
            CalibrationView(camera: camera, audio: audio)
        }
    }
}

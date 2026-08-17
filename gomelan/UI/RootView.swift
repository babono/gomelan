//
//  RootView.swift
//  gomelan
//
//  Hosts the app state machine (PRD §13.4) and owns the shared capture/audio
//  services so they persist across screen transitions.
//
//  One ground for the whole app. There used to be two surfaces — cream "paper"
//  for selection, ink "stage" behind the camera — with the background and colour
//  scheme flipping between them. The Sangsih design collapses that: every screen
//  sits on the same warm brown with the pattern drifting behind it, and the
//  camera screens are simply the ones where a live image covers it. The app no
//  longer flashes between light and dark partway through a flow.
//
//  The pattern lives HERE, once, rather than in each screen. It is a single
//  Canvas that persists across navigation, so the drift is continuous through a
//  transition instead of restarting — and screens cannot forget to include it.
//

import SwiftUI

struct RootView: View {
    @State private var app = AppState()
    @State private var camera = CameraController()
    @State private var cue = CuePlayer()
    @State private var audio = AudioEngineController()

    var body: some View {
        ZStack {
            // Skipped where a camera preview fills the screen anyway — painting
            // a pattern that is about to be completely covered is wasted work on
            // exactly the screens with the least headroom to spare.
            if !isCameraScreen {
                PatternBackground()
            } else {
                Theme.ground.ignoresSafeArea()
            }
            content
        }
        .environment(app)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }

    /// Screens whose ground is the live camera feed rather than the pattern.
    private var isCameraScreen: Bool {
        switch app.screen {
        case .framing, .aligning, .calibrating, .baseline, .watching,
             .countdown, .playing, .malletTest, .detectionTest, .audioTest,
             .captureTraining:
            return true
        default:
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
        case .chooseCycles:
            ChooseCyclesView()
        case .watching:
            WatchView(camera: camera, cue: cue)
        case .countdown, .playing:
            PlayView(camera: camera, audio: audio, cue: cue)
        case .results:
            ResultsView()
        case .settings:
            SettingsView()
        case .baseline:
            StrikeBaselineView(camera: camera, audio: audio)
        case .malletTest:
            MalletTestView(camera: camera)
        case .detectionTest:
            DetectionTestView(camera: camera, audio: audio)
        case .audioTest:
            AudioTestView(audio: audio)
        case .captureTraining:
            CaptureTrainingView(camera: camera, audio: audio)
        }
    }
}

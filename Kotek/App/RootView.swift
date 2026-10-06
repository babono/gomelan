//
//  RootView.swift
//  Kotek
//
//  Hosts the app state machine (PRD §13.4) and owns the shared capture/audio
//  services so they persist across screen transitions.
//
//  One ground for the whole app. There used to be two surfaces — cream "paper"
//  for selection, ink "stage" behind the camera — with the background and colour
//  scheme flipping between them. The Kotek design collapses that: every screen
//  sits on the same warm brown with the pattern drifting behind it, and the
//  camera screens are simply the ones where a live image covers it. The app no
//  longer flashes between light and dark partway through a flow.
//
//  The pattern lives HERE, once, rather than in each screen. It is a single
//  Canvas that persists across navigation, so the drift is continuous through a
//  transition instead of restarting — and screens cannot forget to include it.
//

import SwiftUI
import FactoryKit

struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var preloader = Container.shared.preloaderService()

    var body: some View {
        ZStack {
            // Skipped where a camera preview fills the screen anyway — painting
            // a pattern that is about to be completely covered is wasted work on
            // exactly the screens with the least headroom to spare.
            if !app.screen.isCameraScreen {
                PatternBackground()
            } else {
                Theme.ground.ignoresSafeArea()
            }
            content
        }
        // The hand-over from the splash.
        //
        // The splash sits OVER the app rather than replacing it, so the landing
        // screen is already laid out and drawn underneath by the time the splash
        // starts to go. Both screens put the wordmark in the same place (see
        // `KotekWordmark`), so what actually crosses over is everything around
        // it — the pattern, the button — while the wordmark
        // appears to stay still and simply finish filling.
        //
        // Only the splash animates; the landing screen is revealed rather than
        // moved. Sliding or scaling it would drag the wordmark with it and
        // break exactly the illusion this is for.
        .overlay {
            if let guide = app.visibleGuide {
                GuideView(guide: guide) {
                    withAnimation(.easeInOut(duration: 0.2)) { app.closeGuide() }
                }
            }
        }
        // ABOVE the guides: this one is the whole screen, and a panel showing
        // through it would be a panel nobody asked for.
        .overlay {
            if app.showingOnboarding {
                OnboardingView { app.closeOnboarding() }
            }
        }
        // BELOW both, so a first run shows the splash finish and hand over to
        // the introduction rather than the introduction appearing behind it.
        .overlay {
            if !preloader.isFinished {
                SplashView(progress: preloader.progress)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.visibleGuide)
        .animation(.easeInOut(duration: 0.3), value: app.showingOnboarding)
        .animation(.easeInOut(duration: 0.55), value: preloader.isFinished)
        .task {
            await preloader.warm(camera: Container.shared.cameraService())
            // Raised BEFORE the splash finishes fading, deliberately: the
            // introduction is laid out and drawn underneath it, and the splash
            // reveals it. Waiting for the fade to end instead would show the
            // landing screen for half a second and then cover it up.
            app.showOnboardingIfFirstRun()
        }
        // Switch the camera off the moment the app leaves the screens that show
        // one. Nothing ever called `camera.stop()` — the session ran from the
        // framing step until the app was killed, through the kotekan picker,
        // the results screen and settings, which is why the phone got hot.
        //
        // It belongs HERE rather than in each screen's `onDisappear`, for the
        // same reason the pattern does: this is the one place that knows what
        // the app is showing. A per-screen teardown would also have to know it
        // was NOT handing over to another camera screen, and getting that wrong
        // in either direction is either a dead preview or a hot phone.
        //
        // Camera-to-camera moves (aligning → baseline, countdown → playing) do
        // not flip this, so the session is never stopped and restarted mid-flow.
        .onChange(of: app.screen.isCameraScreen) { _, showsCamera in
            if !showsCamera {
                Container.shared.cameraService().stop()
            }
        }
        // Every switch under here ticks like a kajar when it flips. Buttons get
        // the same treatment one at a time (`.buttonStyle(.kajar)`), because
        // each of them already names a style and the nearest one wins; toggles
        // name none, so the environment reaches all of them from here.
        .toggleStyle(.kajar)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch app.screen {
        case .welcome:
            WelcomeView()
        case .checkingPermissions:
            PermissionsView()
        case .permissionsBlocked:
            PermissionsBlockedView()
        case .chooseInstrument:
            ChooseInstrumentView()
        case .choosingKeyCount:
            KeyCountView()
        case .framing:
            FramingView()
        case .aligning:
            AligningView()
        case .calibrating:
            CalibrationView()
        case .chooseKotekan:
            ChooseKotekanView()
        case .countdown, .playing:
            PlayView()
        case .results:
            ResultsView()
        case .settings:
            SettingsView()
        case .baseline:
            StrikeBaselineView()
        case .malletTest:
            MalletTestView()
        case .detectionTest:
            DetectionTestView()
        case .audioTest:
            AudioTestView()
        case .captureTraining:
            CaptureTrainingView()
        }
    }
}

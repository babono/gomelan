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

import FactoryKit
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var preloader = Container.shared.preloaderService()
    @Environment(\.scenePhase) private var scenePhase
    @State private var splashGone = false

    var body: some View {
        ZStack {
            // Held back until the splash has opened — see `shown`.
            PatternBackground(shown: splashGone)
            content
        }
        // The hand-over from the splash.
        //
        // The splash sits OVER the app rather than replacing it, so the landing
        // screen is already laid out and drawn underneath by the time the splash
        // starts to go. The splash ends on its gate swinging open, and the
        // landing screen draws that same gate, open, in the same place (see
        // `PuraGate`) — so what the opening reveals is the landing screen
        // itself, and when the splash goes, nothing moves.
        //
        // The one movement the landing screen makes is the approach: its
        // wordmark and gangsa are drawn small behind the distant gate and grow
        // to full size as the splash's gate grows and opens — the same zoom,
        // about the same point (the middle of the bottom edge), in the same
        // animation (see `WelcomeView.zoom`). Its own gate and its buttons
        // wait for the camera to arrive.
        .overlay {
            if let guide = app.visibleGuide {
                GuideView(guide: guide) {
                    withAnimation(.easeInOut(duration: 0.2)) { app.closeGuide() }
                }
            }
        }
        // A controller with a PIN this phone doesn't have. Here rather than on
        // each screen: RootView follows the active gangsa's controller from
        // every one of them, so any of them can be the one that meets it.
        .overlay {
            if app.sensor.status == .locked, let info = app.sensor.info {
                ControllerPINDialog(mode: .unlock, controllerName: info.name, sensor: app.sensor) {
                    app.sensor.skipPIN()
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
        // A shared kotekan's link, over whatever screen it found. Waits for the
        // splash, the introduction and the welcome screen's account choice:
        // adding it needs someone to add it for. Off the profile step too — a
        // first Apple sign-in lands there, and Add would jump past it.
        .overlay {
            if let id = app.pendingShare, app.account != nil, splashGone, !app.showingOnboarding,
               app.screen != .welcome, app.screen != .profileSetup
            {
                AddSharedKotekanView(id: id, app: app)
                    .id(id)
            }
        }
        // Copying a figure of the player's own to another gangsa: the same
        // screen, from the picker's card menu.
        .overlay {
            if let k = app.copyingKotekan {
                AddSharedKotekanView(copying: k, app: app)
                    .id(k.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.copyingKotekan?.id)
        .onOpenURL { app.openSharedKotekan($0) }
        // Account work can start on several screens — welcome, Settings, the
        // results screen's save prompt — so its scrim and the switch question
        // live here, once, rather than in each of them.
        .busy(app.accountBusy)
        .confirm(
            Binding(
                get: { app.pendingSwitch != nil },
                set: { if !$0 { app.pendingSwitch = nil } }
            ),
            title: "This Apple ID already has an account",
            message: "Switch to it? The gangsa and records on this iPhone will be removed.",
            confirmTitle: "Switch account",
            kipli: .sad
        ) { [pending = app.pendingSwitch] in
            // Captured here: the switch runs in a Task, after the dialog has
            // closed and cleared the binding — and with it `pendingSwitch`.
            guard let pending else { return }
            Task { await app.confirmSwitch(pending) }
        }
        // ABOVE both, so a first run shows the splash open and hand over to
        // the introduction rather than the introduction appearing over it.
        // The splash removes itself once its gate is open, rather than fading
        // out when loading ends — see `SplashView`.
        .overlay {
            if !splashGone {
                SplashView(
                    finished: preloader.isFinished,
                    // Inside the splash's opening animation: see `onOpen`.
                    onOpen: { app.splashCovering = false },
                    onArrive: { app.splashGateOpen = true },
                    onDone: { splashGone = true }
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.visibleGuide)
        .animation(.easeInOut(duration: 0.3), value: app.showingOnboarding)
        .task {
            await preloader.warm()
            // Raised BEFORE the splash finishes fading, deliberately: the
            // introduction is laid out and drawn underneath it, and the splash
            // reveals it. Waiting for the fade to end instead would show the
            // landing screen for half a second and then cover it up.
            app.showOnboardingIfFirstRun()
        }
        // The strike controller follows the active gangsa (Flow E), from here
        // because this is the one place that sees every screen and every
        // instrument switch. Gangsa A →
        // B on the same controller keeps the connection (`GangsaSensor.use`).
        // The setup screen and the sensor test drive it themselves (nil).
        .onChange(of: app.sensorTarget, initial: true) { _, target in
            if let target { app.sensor.use(target) }
        }
        // Foreground only: nothing here needs strikes while the app is away,
        // and coming back reconnects on its own.
        .onChange(of: scenePhase) { _, phase in
            guard let target = app.sensorTarget else { return }
            app.sensor.use(phase == .background ? .none : target)
        }
        // Every switch under here ticks like a kajar when it flips. Buttons get
        // the same treatment one at a time (`.buttonStyle(.appPlain)`), because
        // each of them already names a style and the nearest one wins; toggles
        // name none, so the environment reaches all of them from here.
        .toggleStyle(.app)
        .preferredColorScheme(.light)
        .statusBarHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch app.screen {
        case .welcome:
            WelcomeView()
        case .profileSetup:
            ProfileSetupView()
        case .chooseInstrument:
            ChooseInstrumentView()
        case .choosingKeyCount:
            KeyCountView()
        case .chooseKotekan:
            ChooseKotekanView()
        case .createKotek:
            CreateKotekView()
        case .results:
            ResultsView()
        case .settings:
            SettingsView()
        case .history:
            PracticeHistoryView()
        case .noteCapture:
            NoteCaptureView()
        case .sensorTest:
            SensorPlayView()
        case .controllerSetup:
            ControllerSetupView()
        case .waterfall:
            WaterfallPlayView()
        case .coopSetup:
            CoopSetupView()
        case .coopPlay:
            CoopPlayView()
        case .learn:
            LearnView()
        }
    }
}

//
//  PlayView.swift
//  Kotek
//
//  THE screen (PRD §4 Flow C). Live camera feed + overlay guidance, driven by
//  the PlayEngine on a display link. The score sits along the bottom showing
//  both halves against the gong cycle; the header counts the passes.
//

import QuartzCore
import SwiftUI

struct PlayView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController
    let audio: AudioEngineController
    let cue: CuePlayer

    var body: some View {
        PlayContentView(app: app, camera: camera, audio: audio, cue: cue)
    }
}

private struct PlayContentView: View {
    let app: AppState
    let camera: CameraController
    let audio: AudioEngineController
    let cue: CuePlayer
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel: PlayViewModel

    init(
        app: AppState,
        camera: CameraController,
        audio: AudioEngineController,
        cue: CuePlayer
    ) {
        self.app = app
        self.camera = camera
        self.audio = audio
        self.cue = cue
        _viewModel = State(
            wrappedValue: PlayViewModel(app: app, camera: camera, audio: audio, cue: cue)
        )
    }

    var body: some View {
        @Bindable var vm = viewModel
        @Bindable var bindableApp = app

        return ZStack {
            // 1. Camera preview edge-to-edge
            CameraPreview(camera: camera, forwardsRotation: true)
                .ignoresSafeArea()

            // 2. Key rect guidance overlay edge-to-edge
            OverlayView(keys: app.profile.keys, engine: vm.engine)
                .ignoresSafeArea()

            // 3. Floating chrome (top bar, then session controls & river score)
            VStack(spacing: 0) {
                PlayTopBar(
                    title: vm.sessionTitle,
                    engine: vm.engine,
                    record: vm.record,
                    bottomBarVisible: $bindableApp.bottomBarVisible,
                    onPause: { vm.pause() }
                )
                .background(Theme.ink.opacity(0.75))

                Spacer()

                if app.bottomBarVisible {
                    PlayBottomBar(
                        app: app,
                        engine: vm.engine,
                        keyRange: vm.keyRange
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: app.bottomBarVisible)

            // Countdown pre-roll overlay
            if let startCue = vm.startCue, vm.coachStep == nil {
                CountdownOverlay(cue: startCue)
            }

            // Pause overlay
            if vm.paused, vm.coachStep == nil {
                PauseOverlay(
                    onResume: { vm.resume() },
                    onShowAround: { vm.startCoach(startsSession: false) },
                    onEndPractice: {
                        vm.paused = false
                        vm.endPractice()
                    }
                )
            }
        }
        .overlayPreferenceValue(CoachAnchors.self) { anchors in
            GeometryReader { proxy in
                if let coachStep = vm.coachStep {
                    PracticeCoachOverlay(
                        step: coachStep,
                        target: anchors[coachStep].map { proxy[$0] },
                        onNext: { vm.advanceCoach() },
                        onSkip: { vm.finishCoach() }
                    )
                }
            }
            .ignoresSafeArea()
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { vm.handleOverlaySizeChanged(proxy.size) }
                    .onChange(of: proxy.size) { _, new in vm.handleOverlaySizeChanged(new) }
            }
            .ignoresSafeArea()
        }
        .background(Theme.ink)
        .onAppear { vm.setup() }
        .onDisappear { vm.teardown() }
        .task { await vm.runVisionDetection() }
        .onChange(of: app.chosenHalf) { _, _ in vm.handleChosenHalfChanged() }
        .onChange(of: scenePhase) { _, phase in vm.handleScenePhase(phase) }
        .onChange(of: app.tempoScale) { _, new in vm.handleTempoScaleChanged(new) }
        .onChange(of: app.yourVoiceAudible) { _, new in vm.engine.yourVoiceAudible = new }
        .onChange(of: app.partnerAudible) { _, new in vm.engine.partnerAudible = new }
    }
}

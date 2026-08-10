//
//  PlayView.swift
//  gomelan
//
//  The core loop screen (PRD §4 Flow C). Live camera feed + overlay guidance,
//  driven by the PlayEngine on a display link. Handles countdown, pause, and the
//  live strike → judgement wiring from the audio engine.
//

import SwiftUI
import QuartzCore

struct PlayView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController
    let audio: AudioEngineController
    let cue: CuePlayer

    @State private var engine = PlayEngine()
    @State private var displayLink = DisplayLink()

    @State private var countdown: Int? = 3
    @State private var paused = false
    @State private var pauseStartedAt: Double = 0

    // Debug HUD (Phase 3, §9): last detected key + confidence.
    @State private var lastKey: Int?
    @State private var lastConfidence: Double = 0

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            OverlayView(keys: app.profile.keys,
                        states: engine.renderStates,
                        approachNotes: engine.approachNotes)
                .ignoresSafeArea()

            topBar

            if let countdown {
                CountdownOverlay(value: countdown)
            }

            if paused {
                pauseOverlay
            }
        }
        .onAppear(perform: setup)
        .onDisappear(perform: teardown)
    }

    // MARK: - Chrome

    private var topBar: some View {
        VStack {
            HStack(alignment: .top) {
                Button {
                    pause()
                } label: {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)

                Spacer()

                debugHUD
            }
            .padding(20)
            Spacer()
        }
    }

    private var debugHUD: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(audio.isRunning ? Theme.hit : Theme.miss)
                .frame(width: 8, height: 8)
            if let lastKey {
                Text("key \(lastKey) · \(Int(lastConfidence * 100))%")
            } else {
                Text("listening…")
            }
        }
        .font(.caption.monospaced())
        .foregroundStyle(.white.opacity(0.7))
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(.black.opacity(0.4), in: Capsule())
    }

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Paused").font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                HStack(spacing: 16) {
                    PrimaryButton(title: "Resume", systemImage: "play.fill") { resume() }
                        .frame(width: 220)
                    SecondaryButton(title: "Quit to songs", systemImage: "xmark") {
                        teardown()
                        app.backToSongs()
                    }
                }
            }
        }
    }

    // MARK: - Lifecycle

    private func setup() {
        camera.start()

        engine.cue = cue
        engine.metronomeEnabled = app.metronomeEnabled
        engine.referenceToneEnabled = app.referenceToneEnabled
        engine.onComplete = { result in
            Task { @MainActor in
                teardown()
                if let result {
                    app.finish(result: result)
                } else {
                    app.backToSongs()
                }
            }
        }

        if let song = app.selectedSong {
            engine.configure(song: song, mode: app.playMode, profile: app.profile, tempoScale: app.tempoScale)
        }

        // Live strikes → judgement. hostTime is captured at detection, so the
        // hop to the main queue doesn't skew timing.
        audio.onStrike = { key, hostTime, confidence in
            Task { @MainActor in
                lastKey = key
                lastConfidence = confidence
                engine.registerStrike(keyIndex: key, hostTime: hostTime, confidence: confidence)
            }
        }
        try? audio.start(profile: app.profile)

        runCountdown()
    }

    private func runCountdown() {
        Task { @MainActor in
            for value in stride(from: 3, through: 1, by: -1) {
                countdown = value
                try? await Task.sleep(for: .seconds(1))
            }
            countdown = nil
            app.countdownFinished()
            engine.start()
            displayLink.onFrame = { now in engine.tick(now: now) }
            displayLink.start()
        }
    }

    private func pause() {
        guard countdown == nil, !paused else { return }
        paused = true
        pauseStartedAt = CACurrentMediaTime()
        displayLink.stop()
        audio.stop()
    }

    private func resume() {
        engine.adjustStart(by: CACurrentMediaTime() - pauseStartedAt)
        try? audio.start(profile: app.profile)
        displayLink.start()
        paused = false
    }

    private func teardown() {
        displayLink.stop()
        audio.onStrike = nil
        audio.stop()
        cue.stop()
    }
}

/// The 3-2-1 countdown over the live feed (§4 Flow C).
private struct CountdownOverlay: View {
    let value: Int
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            Text("\(value)")
                .font(.system(size: 160, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .transition(.scale.combined(with: .opacity))
                .id(value)
        }
    }
}

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
    @State private var fusion: StrikeFusion?
    /// Full-bleed size of the overlay/preview, for the vision crop mapping.
    @State private var overlaySize: CGSize = .zero

    @State private var countdown: Int? = 3
    @State private var paused = false
    @State private var pauseStartedAt: Double = 0

    // Debug HUD (Phase 3, §9): last detected key + confidence.
    @State private var lastKey: Int?
    @State private var lastConfidence: Double = 0
    /// A strike was heard but no template won by enough margin. Distinct from
    /// hearing nothing at all — the two have completely different fixes (an
    /// unclear strike means the calibration cannot separate those keys; silence
    /// means the mic is too far away or the gate is too high), and treating both
    /// as "nothing happened" makes them impossible to tell apart on the day.
    @State private var unclearAt: Double?

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session, controller: camera)
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
        .background {
            // Measures the full-bleed layout the preview/overlay fill, so the
            // vision crop maps back onto the frame in the same coordinate space.
            GeometryReader { proxy in
                Color.clear
                    .onAppear { overlaySize = proxy.size }
                    .onChange(of: proxy.size) { _, new in overlaySize = new }
            }
            .ignoresSafeArea()
        }
        .onChange(of: overlaySize) { _, new in fusion?.viewSize = new }
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
            if unclearAt != nil {
                Text("heard a strike — couldn't tell which key")
            } else if let lastKey {
                Text("key \(lastKey) · \(Int(lastConfidence * 100))%")
            } else {
                Text("listening…")
            }
        }
        .font(.caption.monospaced())
        .foregroundStyle(unclearAt != nil ? Theme.accent : .white.opacity(0.7))
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

        // Vision fusion. viewSize is filled in by the GeometryReader measurement
        // (onChange keeps it current); until then resolve() no-ops safely.
        fusion = StrikeFusion(frames: camera.frameBuffer,
                              keys: app.profile.keys,
                              viewSize: overlaySize)

        // Live strikes → judgement. hostTime is captured at detection, so the
        // hop to the main queue doesn't skew timing.
        audio.onStrike = { key, hostTime, confidence in
            Task { @MainActor in
                lastKey = key
                lastConfidence = confidence
                unclearAt = nil
                engine.registerStrike(keyIndex: key, hostTime: hostTime, confidence: confidence)
            }
        }
        audio.onUnclearStrike = { hostTime, candidates in
            Task { @MainActor in
                // Audio couldn't call the key. Ask vision to break the tie from
                // the frame at this strike's time; only then do we score it.
                if let decision = await fusion?.resolve(candidates: candidates, hostTime: hostTime) {
                    lastKey = decision.keyIndex
                    lastConfidence = decision.hitProbability
                    unclearAt = nil
                    engine.registerStrike(keyIndex: decision.keyIndex, hostTime: hostTime, confidence: decision.hitProbability)
                } else {
                    unclearAt = hostTime
                    // Neither audio nor vision could tell: report nothing rather
                    // than guess a wrong note.
                }
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
        audio.onUnclearStrike = nil
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

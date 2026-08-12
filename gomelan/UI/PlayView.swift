//
//  PlayView.swift
//  gomelan
//
//  The core loop screen (PRD §4 Flow C). Live camera feed + overlay guidance,
//  driven by the PlayEngine on a display link. The river runs along the bottom
//  showing both halves against the gong cycle; the header tracks the cycle
//  count. Handles countdown, pause, and the live strike → judgement wiring from
//  vision (and audio, when a baseline confirms strikes).
//
//  This screen is the player's turn only. Watching and hearing the figure
//  happens first, on its own screen (WatchView), so after the gong count-in the
//  instrument is handed straight over — with your partner's half still playing
//  beside you.
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
    @State private var visionDetector = VisionStrikeDetector()
    @State private var useAudioConfirmation = false
    @State private var overlaySize: CGSize = .zero

    @State private var countdown: Int? = 3
    @State private var paused = false
    @State private var pauseStartedAt: Double = 0

    // Kept for the strike wiring; not surfaced during play (clean overlay).
    @State private var lastKey: Int?
    @State private var lastConfidence: Double = 0
    @State private var unclearAt: Double?

    var body: some View {
        ZStack {
            // 1. Camera preview edge-to-edge
            CameraPreview(session: camera.session, controller: camera)
                .ignoresSafeArea()

            // 2. Key rect guidance overlay edge-to-edge (matching AligningView geometry)
            OverlayView(keys: app.profile.keys, engine: engine)
                .ignoresSafeArea()

            // 3. Floating chrome (top bar + scrolling stroke row). This sits in
            // front of the camera — as a `.background` it was drawn behind the
            // opaque preview layer and never showed up at all.
            VStack(spacing: 0) {
                topBar
                    .background(Theme.ink.opacity(0.75))

                Spacer()

                NotesRiver(engine: engine,
                           keyRange: keyRange,
                           keyCount: app.profile.keys.count,
                           yourHalf: app.chosenHalf)
            }

            if countdown == nil, !paused {
                phaseBanner
            }

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
        .background(Theme.ink)
        .onChange(of: overlaySize) { _, new in
            Task { await fusion?.setViewSize(new) }
        }
        .onAppear(perform: setup)
        .onDisappear(perform: teardown)
        .task { await runVisionDetection() }
    }

    // MARK: - Chrome

    private var sessionTitle: String {
        guard let k = app.selectedKotekan else { return "" }
        return "\(k.name) · \(app.chosenHalf.title)"
    }

    private var topBar: some View {
        HStack {
            Text(sessionTitle)
                .font(.sans(13, weight: .semibold))
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(Theme.copper)

            Spacer()

            // Its own view so the clock ticking doesn't re-evaluate the whole
            // screen sixty times a second just to move a counter.
            CycleCounter(engine: engine,
                         strokesPerCycle: max(1, app.selectedKotekan?.strokeCount(app.chosenHalf) ?? 1),
                         totalCycles: app.chosenCycles)

            Spacer()

            Button { pause() } label: {
                Image(systemName: "xmark")
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.cream)
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cream.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    /// Names the current session phase so the demo → hand-over reads clearly.
    /// Uses the shared `PhaseBanner` chrome component.
    private var phaseBanner: some View {
        VStack {
            Spacer().frame(height: 70)
            PhaseBanner(phase: engine.phase)
                .animation(.easeInOut(duration: 0.25), value: engine.phase)
            Spacer()
        }
    }

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 24) {
                Text("Paused").font(.serif(44)).foregroundStyle(Theme.cream)
                HStack(spacing: 16) {
                    PillButton(title: "Resume", style: .filled) { resume() }
                    PillButton(title: "Watch again", style: .outlined, tint: Theme.copper) {
                        teardown()
                        app.watchAgain()
                    }
                    PillButton(title: "Quit", style: .outlined, tint: Theme.copper) {
                        teardown()
                        app.backToKotekan()
                    }
                }
            }
        }
    }

    // MARK: - The river (§13.5)

    /// The lanes the river draws — both halves of the figure.
    private var keyRange: ClosedRange<Int> {
        app.selectedKotekan?.voicedKeyRange ?? 0...max(0, app.profile.keys.count - 1)
    }

    /// The bilah YOUR half strikes — the only ones vision needs to classify.
    private var playedKeys: Set<Int> {
        guard let k = app.selectedKotekan else { return [] }
        return Set(k.pattern(app.chosenHalf).compactMap { $0 })
    }

    // MARK: - Lifecycle

    private func setup() {
        camera.start()
        camera.enableContinuousAutoFocus()

        engine.cue = cue
        engine.metronomeEnabled = app.metronomeEnabled
        engine.referenceToneEnabled = app.referenceToneEnabled
        if let k = app.selectedKotekan {
            engine.sessionSubtitle = "\(k.name) · \(app.chosenHalf.title) · \(app.chosenCycles)×"
        }
        engine.onComplete = { result in
            Task { @MainActor in
                teardown()
                if let result { app.finish(result: result) } else { app.backToKotekan() }
            }
        }

        // Your partner keeps playing the other half beside you (§7), unless it
        // has been turned off in settings.
        engine.partnerAudible = app.partnerAudible
        if let song = app.selectedSong {
            engine.configure(song: song, partner: app.partnerSong, mode: app.playMode,
                             profile: app.profile, tempoScale: app.tempoScale, role: .practice)
        }

        let fusion = StrikeFusion(frames: camera.frameBuffer,
                                  keys: app.profile.keys,
                                  viewSize: overlaySize)
        self.fusion = fusion
        // Only the bilah this figure uses are worth classifying — three or four
        // instead of ten, which is most of the vision cost gone.
        let active = playedKeys
        Task { await fusion.setActiveKeys(active) }

        visionDetector.reset()
        try? audio.start(profile: app.profile)
        if let baseline = app.profile.strikeBaseline {
            audio.setBaselineTemplate(baseline)
        }

        // Wire audio onset detection to immediately resolve key via vision:
        audio.onStrikeDetected = { hostTime in
            Task { @MainActor in
                guard countdown == nil, !paused, !engine.isFinished else { return }
                if let decision = await fusion.resolveVisionFirst(hostTime: hostTime) {
                    applyStrike(key: decision.keyIndex, hostTime: hostTime, confidence: decision.hitProbability)
                }
            }
        }

        useAudioConfirmation = app.requireStrikeSound && (audio.hasStrikeBaseline || app.profile.hasLearnedBaseline)
        if useAudioConfirmation {
            audio.onConfirmedStrike = { hostTime in
                Task { @MainActor in
                    guard countdown == nil, !paused, !engine.isFinished else { return }
                    if let decision = await fusion.resolveVisionFirst(hostTime: hostTime) {
                        applyStrike(key: decision.keyIndex, hostTime: hostTime, confidence: decision.hitProbability)
                    }
                }
            }
        }

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

    /// The self-triggering vision loop. `latestScores` now suspends onto the
    /// fusion actor, so the inference happens off the main thread and the poll
    /// returns nil immediately when the camera has not delivered a new frame.
    private func runVisionDetection() async {
        while !Task.isCancelled {
            if countdown == nil, !paused, !engine.isFinished,
               let (scores, hostTime) = await fusion?.latestScores() {
                let fired = visionDetector.process(scores: scores)
                if let key = fired.max(by: { (scores[$0] ?? 0) < (scores[$1] ?? 0) }) {
                    let strikeTime = audio.nearestOnset(to: hostTime, within: 0.12) ?? hostTime
                    applyStrike(key: key, hostTime: strikeTime, confidence: scores[key] ?? 1)
                }
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func applyStrike(key: Int, hostTime: Double, confidence: Double) {
        lastKey = key
        lastConfidence = confidence
        unclearAt = nil
        engine.registerStrike(keyIndex: key, hostTime: hostTime, confidence: confidence)
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
        visionDetector.reset()
        displayLink.start()
        paused = false
    }

    private func teardown() {
        displayLink.stop()
        audio.onStrikeDetected = nil
        audio.onConfirmedStrike = nil
        audio.stop()
        cue.stop()
    }
}

/// "Cycle 3 / 8" — which time round the gong cycle the player is on, counted in
/// strokes of the chosen half rather than wall-clock time, so the count-in
/// doesn't bleed into it. Reads the engine itself to keep the per-frame
/// invalidation off the rest of the screen.
private struct CycleCounter: View {
    let engine: PlayEngine
    let strokesPerCycle: Int
    let totalCycles: Int

    var body: some View {
        let cycle = min(totalCycles, Int(max(0, engine.noteProgress)) / strokesPerCycle + 1)
        Text("Cycle \(cycle) / \(totalCycles)")
            .font(.sans(14))
            .foregroundStyle(Theme.inkStone)
    }
}

/// The 3-2-1 countdown over the live feed (§4 Flow C).
private struct CountdownOverlay: View {
    let value: Int
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            Text("\(value)")
                .font(.serif(160, weight: .regular))
                .foregroundStyle(Theme.cream)
                .transition(.scale.combined(with: .opacity))
                .id(value)
        }
    }
}

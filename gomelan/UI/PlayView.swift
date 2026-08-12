//
//  PlayView.swift
//  gomelan
//
//  The core loop screen (PRD §4 Flow C). Live camera feed + overlay guidance,
//  driven by the PlayEngine on a display link. A stroke timeline runs along the
//  bottom showing the kotekan half's figure and the current strike; the header
//  tracks the gong cycle. Handles countdown, pause, and the live strike →
//  judgement wiring from vision (and audio, when a baseline confirms strikes).
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
            OverlayView(keys: app.profile.keys, states: engine.renderStates)
                .ignoresSafeArea()

            // Geometry measurement over full screen coordinate space
            GeometryReader { proxy in
                Color.clear
                    .onAppear { overlaySize = proxy.size }
                    .onChange(of: proxy.size) { _, new in overlaySize = new }
            }
            .ignoresSafeArea()

            // 3. Floating Chrome (TopBar + Marquee Note Train Track)
            VStack(spacing: 0) {
                topBar
                    .background(Theme.ink.opacity(0.75))

                Spacer()

                strokeTimeline
            }

            if let countdown { CountdownOverlay(value: countdown) }
            if paused { pauseOverlay }
        }
        .background(Theme.ink)
        .onChange(of: overlaySize) { _, new in fusion?.viewSize = new }
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

            Text("Cycle \(currentCycle) / \(app.chosenCycles)")
                .font(.sans(14))
                .foregroundStyle(Theme.inkStone)

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

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 24) {
                Text("Paused").font(.serif(44)).foregroundStyle(Theme.cream)
                HStack(spacing: 16) {
                    PillButton(title: "Resume", style: .filled) { resume() }
                    PillButton(title: "Quit", style: .outlined, tint: Theme.copper) {
                        teardown()
                        app.backToKotekan()
                    }
                }
            }
        }
    }

    // MARK: - Stroke timeline (§13.5)

    /// Milliseconds elapsed clamped so the timeline behaves before the start.
    private var elapsedMs: Double { max(0, engine.currentTimeMs) }

    private var currentCycle: Int {
        guard let k = app.selectedKotekan, k.cycleMs > 0 else { return 1 }
        return min(app.chosenCycles, Int(elapsedMs / Double(k.cycleMs)) + 1)
    }

    /// (slot, keyIndex) for every stroke the chosen half plays in a cycle.
    private var cycleStrokes: [(slot: Int, key: Int)] {
        guard let k = app.selectedKotekan else { return [] }
        return k.pattern(app.chosenHalf).enumerated().compactMap { slot, v in
            v.map { (slot, $0) }
        }
    }

    private var activeSlotInCycle: Int {
        guard let k = app.selectedKotekan, k.strokeMs > 0 else { return 0 }
        return Int(elapsedMs / Double(k.strokeMs)) % Kotekan.strokesPerCycle
    }

    /// Index into `cycleStrokes` of the stroke nearest the playhead.
    private var activeStrokeIndex: Int? {
        let strokes = cycleStrokes
        guard !strokes.isEmpty else { return nil }
        return strokes.indices.min {
            abs(strokes[$0].slot - activeSlotInCycle) < abs(strokes[$1].slot - activeSlotInCycle)
        }
    }

    /// All notes in the current song session.
    private var allSessionNotes: [Note] {
        app.selectedSong?.notes ?? []
    }

    /// Current note index progress along the marquee train.
    private var currentProgress: Double {
        if app.playMode == .practice {
            return Double(engine.practiceIndex)
        } else {
            guard let song = app.selectedSong, !song.notes.isEmpty else { return 0 }
            let strokeMs = Double(app.selectedKotekan?.strokeMs ?? 300) / app.tempoScale
            return max(0, engine.currentTimeMs / max(1, strokeMs))
        }
    }

    private var strokeTimeline: some View {
        HStack(spacing: 16) {
            // Current strike, big.
            VStack(alignment: .leading, spacing: 2) {
                Text("STRIKE")
                    .font(.sans(10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Theme.inkStone)
                Text(activeStrokeLabel)
                    .font(.serif(36, weight: .bold))
                    .foregroundStyle(Theme.cream)
                    .contentTransition(.numericText())
            }
            .frame(width: 64, alignment: .leading)

            // Vertical copper strike indicator line on the left
            Rectangle()
                .fill(Theme.copper)
                .frame(width: 2, height: 40)

            // Marquee Train: Notes flow continuously from RIGHT to LEFT towards the strike line
            GeometryReader { geo in
                let notes = allSessionNotes
                let noteSpacing: CGFloat = 56
                let strikeX: CGFloat = 22
                let progress = currentProgress
                let viewportWidth = geo.size.width

                ZStack(alignment: .leading) {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { i, note in
                        let delta = Double(i) - progress
                        let xPos = strikeX + delta * noteSpacing

                        if xPos >= -50 && xPos <= viewportWidth + 50 {
                            let isFirst = abs(delta) < 0.5

                            HStack(spacing: 0) {
                                strokeCircle(isFirst: isFirst, key: note.keyIndex)

                                if i < notes.count - 1 {
                                    Text("·")
                                        .font(.sans(18, weight: .bold))
                                        .foregroundStyle(Theme.copper.opacity(0.5))
                                        .frame(width: noteSpacing - (isFirst ? 42 : 36))
                                }
                            }
                            .position(x: xPos + (isFirst ? 21 : 18), y: geo.size.height / 2)
                        }
                    }
                }
            }
            .frame(height: 48)
            .clipped()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.inkRaised.opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(Theme.copper.opacity(0.2)).frame(height: 1) }
        .animation(.snappy(duration: 0.25), value: engine.practiceIndex)
    }

    private var activeStrokeLabel: String {
        guard let i = activeStrokeIndex else { return "–" }
        return bilahLabel(cycleStrokes[i].key, count: app.profile.keys.count)
    }

    private func strokeCircle(isFirst: Bool, key: Int) -> some View {
        let label = bilahLabel(key, count: app.profile.keys.count)
        return Text(label)
            .font(.serif(isFirst ? 18 : 15, weight: .bold))
            .foregroundStyle(isFirst ? Theme.cream : Theme.copper)
            .frame(width: isFirst ? 42 : 36, height: isFirst ? 42 : 36)
            .background {
                if isFirst {
                    Circle()
                        .fill(Theme.terracotta)
                        .shadow(color: Theme.terracotta.opacity(0.6), radius: 6)
                } else {
                    Circle()
                        .strokeBorder(Theme.copper.opacity(0.6), lineWidth: 1.5)
                }
            }
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

        if let song = app.selectedSong {
            engine.configure(song: song, mode: app.playMode, profile: app.profile, tempoScale: app.tempoScale)
        }

        fusion = StrikeFusion(frames: camera.frameBuffer,
                              keys: app.profile.keys,
                              viewSize: overlaySize)

        visionDetector.reset()
        try? audio.start(profile: app.profile)
        if let baseline = app.profile.strikeBaseline {
            audio.setBaselineTemplate(baseline)
        }

        // Wire audio onset detection to immediately resolve key via vision:
        audio.onStrikeDetected = { hostTime in
            Task { @MainActor in
                guard countdown == nil, !paused, !engine.isFinished else { return }
                if let decision = await fusion?.resolveVisionFirst(hostTime: hostTime) {
                    applyStrike(key: decision.keyIndex, hostTime: hostTime, confidence: decision.hitProbability)
                }
            }
        }

        useAudioConfirmation = app.requireStrikeSound && (audio.hasStrikeBaseline || app.profile.hasLearnedBaseline)
        if useAudioConfirmation {
            audio.onConfirmedStrike = { hostTime in
                Task { @MainActor in
                    guard countdown == nil, !paused, !engine.isFinished else { return }
                    if let decision = await fusion?.resolveVisionFirst(hostTime: hostTime) {
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

    private func runVisionDetection() async {
        while !Task.isCancelled {
            if countdown == nil, !paused, !engine.isFinished,
               let (scores, hostTime) = fusion?.latestScores() {
                let fired = visionDetector.process(scores: scores)
                if let key = fired.max(by: { (scores[$0] ?? 0) < (scores[$1] ?? 0) }) {
                    let strikeTime = audio.nearestOnset(to: hostTime, within: 0.12) ?? hostTime
                    applyStrike(key: key, hostTime: strikeTime, confidence: scores[key] ?? 1)
                }
            }
            try? await Task.sleep(for: .milliseconds(30))
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

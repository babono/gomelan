//
//  PlayView.swift
//  Kotek
//
//  THE screen (PRD §4 Flow C). Live camera feed + overlay guidance, driven by
//  the PlayEngine on a display link. The score sits along the bottom showing
//  both halves against the gong cycle; the header counts the passes. Handles the
//  countdown and the live strike → judgement wiring from vision (and audio, when
//  a baseline confirms strikes).
//
//  Everything a session used to be configured by now lives HERE, because a
//  gangsa player's verdict on the old flow — kotekan, then which half, then how
//  many cycles, then a demo to sit through — was that it is too much to get
//  through before you can play a note. So:
//
//    · The figure loops until you stop it. There is no cycle count to choose
//      and no end to reach; the counter only goes up.
//    · Which half you play is a toggle up here, swappable mid-cycle without the
//      gong stopping.
//    · The demo is a switch: un-mute your own half and the app plays along.
//    · Scoring happens quietly in the background. Nothing fails, nothing
//      interrupts, and the score is only shown when you end the session.
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

    /// How sure vision must be before its answer is used as a training label for
    /// the audio dictionary. Well above `StrikeFusion.minHitProbability`, which
    /// is the bar for ACTING on a sighting — teaching from a marginal crop would
    /// bake a mistake into a template that then goes on to make more of them.
    private let visionTeachingConfidence: Double = 0.75

    @State private var countdown: Int? = 3

    // Kept for the strike wiring; not surfaced during play (clean overlay).
    @State private var lastKey: Int?
    @State private var lastConfidence: Double = 0
    @State private var unclearAt: Double?

    var body: some View {
        @Bindable var app = app
        return ZStack {
            // 1. Camera preview edge-to-edge
            CameraPreview(camera: camera, forwardsRotation: true)
                .ignoresSafeArea()

            // 2. Key rect guidance overlay edge-to-edge (matching AligningView geometry)
            OverlayView(keys: app.profile.keys, engine: engine)
                .ignoresSafeArea()

            // 3. Floating chrome (top bar, then the session controls and the
            // score along the bottom). This sits in FRONT of the camera — as a
            // `.background` it was drawn behind the opaque preview layer and
            // never showed up at all.
            VStack(spacing: 0) {
                topBar
                    .background(Theme.ink.opacity(0.75))

                Spacer()

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        halfSwitch
                        Spacer()
                        VoiceMixer(yourHalf: app.chosenHalf,
                                   yourVoiceAudible: $app.yourVoiceAudible,
                                   partnerAudible: $app.partnerAudible)
                    }
                    .padding(.horizontal, 24)

                    if app.riverVisible {
                        NotesRiver(engine: engine,
                                   keyRange: keyRange,
                                   keyCount: app.profile.keys.count,
                                   yourHalf: app.chosenHalf)
                    }
                }
            }

            if let countdown {
                CountdownOverlay(value: countdown)
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
        // Swapping halves mid-session. The engine keeps the clock and the score;
        // all this has to do is hand it the new note arrays and re-point vision
        // at the bilah that are now yours to strike.
        .onChange(of: app.chosenHalf) { _, half in
            guard let song = app.selectedSong else { return }
            // The score reports the half you finished on, so the subtitle above
            // it has to name that one and not the one you started with.
            if let k = app.selectedKotekan {
                engine.sessionSubtitle = "\(k.name) · \(half.title)"
            }
            engine.setHalf(song: song, partner: app.partnerSong)
            let active = playedKeys
            Task { await fusion?.setActiveKeys(active) }
            audio.setDecompositionKeys(active)
        }
        .onChange(of: app.yourVoiceAudible) { _, new in engine.yourVoiceAudible = new }
        .onChange(of: app.partnerAudible) { _, new in engine.partnerAudible = new }
    }

    // MARK: - Chrome

    private var sessionTitle: String {
        app.selectedKotekan?.name ?? ""
    }

    /// Change sides without stopping. The gong keeps going, the count keeps
    /// climbing and everything already scored is kept — the engine swaps the
    /// note arrays under a clock that never pauses, so the new half lands on
    /// the same pulse the old one left.
    ///
    /// It sits beside the score rather than in the top bar because the score is
    /// what it changes: tapping Sangsih swaps which row of blocks is solid and
    /// numbered, directly above the control that did it.
    private var halfSwitch: some View {
        HStack(spacing: 0) {
            ForEach([KotekanHalf.polos, .sangsih]) { half in
                let selected = app.chosenHalf == half
                Button { app.setHalf(half) } label: {
                    Text(half.title)
                        .font(.sans(12, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(1.4)
                        .foregroundStyle(selected ? Theme.ink : Theme.copper)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .background(selected ? Theme.copper : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .overlay(Capsule().strokeBorder(Theme.copper.opacity(0.45), lineWidth: 1))
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
            CycleCounter(engine: engine)

            Spacer()

            // Hide the score to give the instrument the whole screen.
            Button { app.riverVisible.toggle() } label: {
                Image(systemName: app.riverVisible ? "rectangle.bottomthird.inset.filled" : "rectangle")
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(app.riverVisible ? Theme.ink : Theme.copper)
                    .frame(width: 40, height: 34)
                    .background(app.riverVisible ? Theme.copper : .clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.copper.opacity(0.6), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)

            // Spelled out, not an X. This is the only way out of a session
            // that never ends by itself, so it has to be findable — and a bare
            // glyph in a corner is too easy to hit by accident for something
            // that closes the thing you are in the middle of doing.
            Button { endPractice() } label: {
                Text("End practice")
                    .font(.sans(13, weight: Theme.buttonWeight))
                    .textCase(.uppercase)
                    .tracking(Theme.buttonTracking)
                    .foregroundStyle(Theme.cream)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.cream.opacity(0.45), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
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
        // This screen DOES classify crops, so the frames are wanted again —
        // the demo screen turns them off on the way in.
        camera.wantsFrames = true
        camera.start()
        if app.fixedMount { camera.lockFocusAndExposure() } else { camera.enableContinuousAutoFocus() }

        engine.cue = cue
        engine.metronomeEnabled = app.metronomeEnabled
        engine.referenceToneEnabled = app.referenceToneEnabled
        if let k = app.selectedKotekan {
            engine.sessionSubtitle = "\(k.name) · \(app.chosenHalf.title)"
        }
        engine.onComplete = { result in
            Task { @MainActor in
                teardown()
                if let result { app.finish(result: result) } else { app.backToKotekan() }
            }
        }

        // Your partner keeps playing the other half beside you (§7) unless it is
        // muted — the mixer on the watch screen carries its choices in here.
        engine.partnerAudible = app.partnerAudible
        engine.yourVoiceAudible = app.yourVoiceAudible
        if let song = app.selectedSong {
            engine.configure(song: song, partner: app.partnerSong,
                             profile: app.profile, tempoScale: app.tempoScale)
        }

        let fusion = StrikeFusion(frames: camera.frameBuffer,
                                  keys: app.profile.keys,
                                  viewSize: overlaySize)
        self.fusion = fusion
        // Only the bilah this figure uses are worth classifying — three or four
        // instead of ten, which is most of the vision cost gone.
        let active = playedKeys
        Task {
            await fusion.setActiveKeys(active)
            // Whatever was tuned in the detection screen governs play too —
            // otherwise that screen measures a detector nobody practises with.
            await fusion.setMinHitProbability(app.visionThreshold)
        }

        visionDetector.reset()
        try? audio.start(profile: app.profile)
        //R Start with an empty ring and no pending onsets. Whatever the mic
        //R picked up before the count-in — the room, the app's own cues coming
        //R back off the speaker — is not the player, and it used to be able to
        //R land as the first strike of the session.
        audio.resetDetector()
        // Let the ear form a second opinion, on the same bilah the eye is watching.
        audio.setKeyOpinionsEnabled(true)
        audio.setDecompositionKeys(active)
        if let baseline = app.profile.strikeBaseline {
            audio.setBaselineTemplate(baseline)
        }

        // Wire audio onset detection to immediately resolve key via vision:
        audio.onStrikeDetected = { hostTime in
            Task { @MainActor in
                guard countdown == nil, !engine.isFinished else { return }
                if let decision = await fusion.resolveVisionFirst(hostTime: hostTime) {
                    applyStrike(key: decision.keyIndex, hostTime: hostTime, confidence: decision.hitProbability)
                    // Tally what the ear would have said, whether or not it is
                    // allowed a vote. Audio disagreeing with a confident sighting
                    // is the most informative event in the whole pipeline, and
                    // without this it happens silently and is lost.
                    audio.noteVisionDecision(decision.keyIndex,
                                             confidence: decision.hitProbability,
                                             at: hostTime)
                    // The eye labels the ear's training data. Only clear sightings
                    // teach — a marginal crop would poison the atom it feeds.
                    if decision.hitProbability >= visionTeachingConfidence {
                        audio.learnKey(decision.keyIndex, at: hostTime)
                    }
                } else if app.audioTriggersStrikes, let heard = audio.keyOpinion(at: hostTime) {
                    audio.noteRecovery()
                    // Vision saw a strike happen but could not say where: the
                    // mallet was occluded, or a hand covered the bar at impact.
                    // Without this the hit is simply dropped and scored as a miss.
                    // Confidence is reported as the ear's share, so the overlay
                    // shows it for what it is — a recovered strike, not a sighting.
                    applyStrike(key: heard.keyIndex, hostTime: hostTime,
                                confidence: Double(heard.share))
                }
            }
        }

        useAudioConfirmation = app.requireStrikeSound && (audio.hasStrikeBaseline || app.profile.hasLearnedBaseline)
        if useAudioConfirmation {
            audio.onConfirmedStrike = { hostTime in
                Task { @MainActor in
                    guard countdown == nil, !engine.isFinished else { return }
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
            // Silent when the ear owns the trigger. A presence model's score
            // stays high while the mallet lingers, so a rising-edge detector
            // fires once, latches, and then only ever adds phantoms.
            if !app.audioTriggersStrikes,
               countdown == nil, !engine.isFinished,
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

    /// End the session and go to the score. `engine.end()` calls back through
    /// `onComplete`, which tears down and navigates — so there is one exit path
    /// whether the player pressed the button or something else stopped the run.
    private func endPractice() {
        guard countdown == nil else { return }
        displayLink.stop()
        engine.end()
    }

    private func teardown() {
        displayLink.stop()
        audio.onStrikeDetected = nil
        audio.onConfirmedStrike = nil

        // Keep what the session taught. Without this the dictionary starts empty
        // every time and never gets past its first four strikes per key, which
        // is the whole reason it can improve at all.
        audio.learnedTemplates { templates in
            guard !templates.isEmpty else { return }
            app.storeLinearTemplates(templates)
        }
        audio.setKeyOpinionsEnabled(false)
        audio.stop()
        cue.stop()
    }
}

/// "Cycle 12" — how many times round the figure has been. No denominator: the
/// session runs until the player stops it, so there is nothing to be out of.
///
/// Reads the engine itself to keep the per-frame invalidation off the rest of
/// the screen.
private struct CycleCounter: View {
    let engine: PlayEngine

    var body: some View {
        Text(engine.phase == .countIn ? "Count-in" : "Cycle \(engine.loopIndex + 1)")
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

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
    @Environment(\.scenePhase) private var scenePhase
    let camera: CameraController
    let audio: AudioEngineController
    let cue: CuePlayer

    @State private var engine = PlayEngine()
    @State private var displayLink = DisplayLink()
    @State private var fusion: StrikeFusion?
    @State private var visionDetector = VisionStrikeDetector()
    @State private var overlaySize: CGSize = .zero

    /// How sure vision must be before its answer is used as a training label for
    /// the audio dictionary. Well above `StrikeFusion.minHitProbability`, which
    /// is the bar for ACTING on a sighting — teaching from a marginal crop would
    /// bake a mistake into a template that then goes on to make more of them.
    private let visionTeachingConfidence: Double = 0.75

    @State private var countdown: Int? = 3
    @State private var paused = false
    /// The control tour, when it is running. See `PracticeCoach`.
    @State private var coachStep: CoachStep?
    /// Whether finishing the tour should start the session. True on a first run,
    /// false when it was asked for from the pause overlay — where the session is
    /// already going and the player just wants reminding what a button does.
    @State private var coachStartsSession = false
    /// The panel's state before the tour forced it open, restored afterwards.
    @State private var panelWasVisible = false
    @State private var pauseStartedAt: Double = 0

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

                // The controls and the score are ONE panel, shown and hidden
                // together. They used to be separate — the score had a toggle
                // and the controls were always up — which meant the "give the
                // instrument the whole screen" button left a row of chrome
                // behind and did not do what it said.
                if app.bottomBarVisible {
                    // ONE slab, not a floating row above a backed one. The
                    // controls used to sit bare over the camera feed, which put
                    // outlined pills and small type straight on top of the
                    // outlined bilah — two sets of thin copper lines in the same
                    // place, and the mixer chips landed unreadable across keys 8
                    // and 9. They carry the score's own ground now, and the
                    // score's top hairline falls between them as a divider.
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            halfSwitch.coachTarget(.half)
                            tempoPicker.coachTarget(.tempo)
                            Spacer()
                            VoiceMixer(yourHalf: app.chosenHalf,
                                       yourVoiceAudible: $app.yourVoiceAudible,
                                       partnerAudible: $app.partnerAudible)
                                .coachTarget(.voices)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(Theme.inkRaised.opacity(0.8))

                        NotesRiver(engine: engine,
                                   keyRange: keyRange,
                                   keyCount: app.profile.keys.count,
                                   yourHalf: app.chosenHalf)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: app.bottomBarVisible)

            //R Hidden while the tour runs: on a first session the countdown has
            //R not started, and a frozen "3" behind the dim reads as a stall.
            if let countdown, coachStep == nil {
                CountdownOverlay(value: countdown)
            }

            //R Likewise the pause card — the tour is reachable from it, and two
            //R dimming layers would leave every lit control in shadow.
            if paused, coachStep == nil { pauseOverlay }
        }
        .overlayPreferenceValue(CoachAnchors.self) { anchors in
            //R Full-bleed, and the anchors are resolved against THIS proxy. A
            //R safe-area-inset reader left undimmed strips down both edges and
            //R along the bottom — and worse, would resolve every target into a
            //R space offset from the one the spotlight is drawn in.
            GeometryReader { proxy in
                if let coachStep {
                    PracticeCoachOverlay(step: coachStep,
                                         target: anchors[coachStep].map { proxy[$0] },
                                         onNext: advanceCoach,
                                         onSkip: finishCoach)
                }
            }
            .ignoresSafeArea()
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
        .onChange(of: app.chosenHalf) { _, _ in
            guard let song = app.selectedSong else { return }
            engine.sessionSubtitle = sessionSubtitle
            engine.setHalf(song: song, partner: app.partnerSong)
            let active = playedKeys
            Task { await fusion?.setActiveKeys(active) }
            audio.setDecompositionKeys(active)
        }
        //R Leaving the app pauses the session. Nobody plays a gangsa with the
        //R phone in their pocket, and the clock would otherwise run on and score
        //R every stroke of the absence as a miss — on top of coming back to an
        //R audio engine iOS stopped underneath us.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { pause() }
        }
        .onChange(of: app.tempoScale) { _, new in
            engine.setTempoScale(new)
            engine.sessionSubtitle = sessionSubtitle
        }
        .onChange(of: app.yourVoiceAudible) { _, new in engine.yourVoiceAudible = new }
        .onChange(of: app.partnerAudible) { _, new in engine.partnerAudible = new }
    }

    // MARK: - Chrome

    private var sessionTitle: String {
        app.selectedKotekan?.name ?? ""
    }

    /// What the results screen is a score OF. Both the half and the speed are
    /// in it because the score is parked per half AND per speed — eight cycles
    /// at 0.5× and eight at 1.5× are not the same achievement, and a headline
    /// number that does not say which one it belongs to invites the comparison
    /// it cannot support.
    /// The record for exactly what is being played — this figure, this half,
    /// this speed. Read here rather than inside the counter so the counter can
    /// stay a leaf that only ever reads the engine.
    private var record: Double? {
        guard let k = app.selectedKotekan else { return nil }
        return app.profile.record(kotekanId: k.id,
                                  half: app.chosenHalf.rawValue,
                                  tempo: app.tempoScale)?.accuracy
    }

    private var sessionSubtitle: String {
        let name = app.selectedKotekan?.name ?? ""
        return "\(name) · \(app.chosenHalf.title) · \(Theme.tempoLabel(app.tempoScale))"
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

    /// Stopped, but not over — and the ONLY way out of a session.
    ///
    /// Ending used to be a button of its own in the top bar, one tap from a
    /// session in progress. Pause is the honest first step: the thing you
    /// actually want nine times in ten is to stop the noise and think, and
    /// making that the button means ending is a decision you take with the
    /// music already off rather than one you can make by mis-tapping.
    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 22) {
                Text("Paused").font(.serif(44)).foregroundStyle(Theme.cream)
                HStack(spacing: 16) {
                    PillButton(title: "Resume", style: .filled) { resume() }
                    PillButton(title: "Show me around", style: .outlined, tint: Theme.copper) {
                        startCoach(startsSession: false)
                    }
                    PillButton(title: "End practice", style: .outlined, tint: Theme.copper) {
                        //R Straight out. Going through `resume()` first would
                        //R boot the mic and let a beat of music through purely
                        //R to stop them again a frame later.
                        paused = false
                        endPractice()
                    }
                }
            }
        }
    }

    /// Speed, as a menu rather than a row of five pills.
    ///
    /// Two segmented controls side by side on a camera screen is more chrome
    /// than the figure can spare, and unlike the half switch this is not a
    /// comparison — you know which speed you want, you just need to reach it.
    /// The current value stays on the button so the setting is readable without
    /// opening anything.
    ///
    /// Changing it never stops the music: the engine rebases its clock so the
    /// beat you are on survives the change. See `PlayEngine.setTempoScale`.
    private var tempoPicker: some View {
        @Bindable var app = app
        return Menu {
            Picker("Tempo", selection: $app.tempoScale) {
                ForEach(Theme.tempoScales, id: \.self) { scale in
                    Text(Theme.tempoLabel(scale)).tag(scale)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "metronome")
                    .font(.symbol(12, weight: .semibold))
                Text(Theme.tempoLabel(app.tempoScale))
                    .font(.sans(12, weight: .semibold))
                    .tracking(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.symbol(9, weight: .semibold))
            }
            .foregroundStyle(Theme.copper)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .overlay(Capsule().strokeBorder(Theme.copper.opacity(0.45), lineWidth: 1))
            .contentShape(Capsule())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Tempo, \(Theme.tempoLabel(app.tempoScale))")
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
            SessionCounters(engine: engine, record: record)

            Spacer()

            // Bring the score and controls up. Down by default: the guidance
            // you actually play from is the bilah lighting up on the instrument
            // in front of you, and the panel covers the part of the frame the
            // gangsa is most likely to be in.
            Button { app.bottomBarVisible.toggle() } label: {
                Image(systemName: app.bottomBarVisible ? "rectangle.bottomthird.inset.filled" : "rectangle")
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(app.bottomBarVisible ? Theme.ink : Theme.copper)
                    .frame(width: 40, height: 34)
                    .background(app.bottomBarVisible ? Theme.copper : .clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.copper.opacity(0.6), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.bottomBarVisible ? "Hide the score" : "Show the score")
            .coachTarget(.panelToggle)
            .padding(.trailing, 10)

            Button { pause() } label: {
                Image(systemName: "pause.fill")
                    .font(.symbol(14, weight: .semibold))
                    .foregroundStyle(Theme.cream)
                    .frame(width: 40, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.cream.opacity(0.45), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pause")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .coachTarget(.session)
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
        engine.sessionSubtitle = sessionSubtitle
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
            await fusion.setMinHitProbability(Detection.namingThreshold(from: app.visionThreshold))
        }

        visionDetector.reset()
        //R The slider on Test Detection governs the session too. It did not:
        //R this detector carried its own hardcoded bars, so the one control
        //R anyone tunes moved a number the play screen never read.
        visionDetector.apply(threshold: app.visionThreshold)
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
                guard countdown == nil, !paused, !engine.isFinished else { return }
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

        //R `onConfirmedStrike` used to be wired here as a THIRD trigger, under
        //R a setting called "require strike sound" — which added strikes rather
        //R than requiring anything, and did the opposite of what its own label
        //R promised. The requirement is a veto now and lives in the vision loop;
        //R the baseline still gates what the ear reports at all, upstream.

        //R The tour holds the session at the gate on a first run. `countdown`
        //R stays at 3 rather than being cleared, so the strike guards keep
        //R blocking while it is up; it simply is not drawn.
        if app.hasSeenPracticeCoach {
            runCountdown()
        } else {
            startCoach(startsSession: true)
        }
    }

    // MARK: - The control tour

    private func startCoach(startsSession: Bool, from first: CoachStep = .session) {
        coachStartsSession = startsSession
        panelWasVisible = app.bottomBarVisible
        withAnimation(.easeInOut(duration: 0.2)) {
            if first.needsPanel { app.bottomBarVisible = true }
            coachStep = first
        }
    }

    private func advanceCoach() {
        guard let coachStep else { return }
        guard let next = CoachStep(rawValue: coachStep.rawValue + 1) else {
            finishCoach()
            return
        }
        withAnimation(.easeInOut(duration: 0.24)) {
            //R The last three steps point at controls inside the panel, so it
            //R has to be up for them to be lit at all.
            if next.needsPanel { app.bottomBarVisible = true }
            self.coachStep = next
        }
    }

    private func finishCoach() {
        app.markPracticeCoachSeen()
        withAnimation(.easeInOut(duration: 0.24)) {
            //R Put the panel back where it was. Leaving it up would quietly undo
            //R the default for every new player, one step after explaining that
            //R the default is down.
            app.bottomBarVisible = panelWasVisible
            coachStep = nil
        }
        if coachStartsSession { runCountdown() }
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
               countdown == nil, !paused, !engine.isFinished,
               let (scores, hostTime) = await fusion?.latestScores() {
                let fired = visionDetector.process(scores: scores,
                                                   expecting: engine.dueKey,
                                                   now: hostTime)
                if let key = fired.max(by: { (scores[$0] ?? 0) < (scores[$1] ?? 0) }) {
                    //R The ear does two jobs here and they are separable. It
                    //R sharpens the TIME — vision fires as the mallet arrives
                    //R over the bar, the attack is the moment that counts — and
                    //R in `heardOnly` it also holds the VETO: a sighting nothing
                    //R was heard for is a mallet moving, not a stroke, and the
                    //R model is not good enough to tell those apart on its own.
                    let onset = audio.nearestOnset(to: hostTime,
                                                   within: Detection.corroborationWindow)
                    if app.requireStrikeSound, onset == nil { continue }
                    applyStrike(key: key, hostTime: onset ?? hostTime,
                                confidence: scores[key] ?? 1)
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
        guard countdown == nil, !paused, !engine.isFinished else { return }
        paused = true
        pauseStartedAt = CACurrentMediaTime()
        displayLink.stop()
        //R The ear goes down too. Left running it spends the pause listening to
        //R the room and to the app's own samples ringing out, and the first
        //R thing after Resume would be an onset that was never a strike.
        audio.stop()
    }

    private func resume() {
        guard paused else { return }
        engine.resumeAfterPause(seconds: CACurrentMediaTime() - pauseStartedAt)
        try? audio.start(profile: app.profile)
        audio.resetDetector()
        visionDetector.reset()
        displayLink.start()
        paused = false
    }

    /// End the session and go to the score. `engine.end()` calls back through
    /// `onComplete`, which tears down and navigates — so there is one exit path
    /// whether the player pressed the button or something else stopped the run.
    private func endPractice() {
        guard countdown == nil, !paused else { return }
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

/// "Cycle 12 · 148 · 86% / 94%" — how far round, how much of it counted, and
/// how close you are to beating this figure.
///
/// No denominator on the cycle: the session runs until the player stops it, so
/// there is nothing to be out of.
///
/// The tick is notes that LANDED, which is what the gangsa's grade is made of.
/// The pair after it is your best eight passes SO FAR against the record for
/// this figure, half and speed.
///
/// Both live numbers only ever go UP, and that is deliberate. A running
/// accuracy is the obvious thing to put here and the wrong one: it falls on
/// every mistake, so it puts a dropping number in front of somebody in the
/// middle of a figure and gives them something to watch that is not the
/// instrument. A best cannot punish you for a bad pass — it just sits there
/// until you beat it. It is also the same number the results screen reports,
/// computed by the same function, so the target you were chasing during play is
/// the score you are shown afterwards.
///
/// One view for all of it, reading the engine itself, so the whole per-frame
/// invalidation stays inside this label instead of redrawing the screen around
/// it sixty times a second.
private struct SessionCounters: View {
    let engine: PlayEngine
    /// The best this figure has ever been played on this gangsa, at this half
    /// and speed. nil until eight consecutive cycles have been played once.
    let record: Double?

    private var beatingRecord: Bool {
        guard let record, let best = engine.bestSoFar else { return false }
        return best >= record
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(engine.phase == .countIn ? "Count-in" : "Cycle \(engine.loopIndex + 1)")
                .foregroundStyle(Theme.inkStone)

            if engine.landedNotes > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.symbol(11, weight: .bold))
                    Text("\(engine.landedNotes)")
                }
                .foregroundStyle(Theme.hit)
                .accessibilityLabel("\(engine.landedNotes) notes landed")
            }

            //R Always drawn, even before a single pass has closed. Two reasons:
            //R the control tour has to have something to point at before the
            //R session has started, and appearing later would shift the whole
            //R cluster sideways the moment the first cycle lands.
            HStack(spacing: 3) {
                Text(engine.bestSoFar.map(percent) ?? "—")
                    .foregroundStyle(beatingRecord ? Theme.hit : Theme.cream)
                if let record {
                    Text("/").foregroundStyle(Theme.inkStone.opacity(0.6))
                    // The bar to clear, in the same gold the trophy uses on the
                    // picker card, so the two read as the same fact.
                    Text(percent(record)).foregroundStyle(Theme.gold)
                }
            }
            .coachTarget(.score)
            .accessibilityLabel(accessibilityLabel)
        }
        .font(.sans(14))
        .contentTransition(.numericText())
        .animation(.snappy(duration: 0.25), value: engine.landedNotes)
        .animation(.snappy(duration: 0.25), value: engine.bestSoFar)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        parts.append(engine.bestSoFar.map { "best so far \(percent($0))" } ?? "no score yet")
        if let record { parts.append("record \(percent(record))") }
        if beatingRecord { parts.append("beating the record") }
        return parts.joined(separator: ", ")
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

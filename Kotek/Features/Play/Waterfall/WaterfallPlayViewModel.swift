//
//  WaterfallPlayViewModel.swift
//  Kotek
//
//  The no-camera practice session: notes fall onto a drawn gangsa, strikes come
//  from the piezo sensors. Same `PlayEngine` as the camera screen, so the
//  count-in, the partner half, the judging and the record it files are the
//  real thing — only where `registerStrike` hears from is different.
//

import FactoryKit
import Foundation
import Observation
import QuartzCore
import SwiftUI

@Observable
@MainActor
final class WaterfallPlayViewModel {
    let app: AppState
    let cue: CuePlayer
    let sensor: GangsaSensor
    let engine = PlayEngine()
    private let displayLink = DisplayLink()
    let voice = VoiceCommandListener()

    /// The Learn step this screen is running, or nil for free play. Fixed for
    /// the screen's life: `LearnView` gives each step a fresh one.
    let lesson: LearnStage?
    /// Build up's place: which of `LearnStage.buildUpTempos`, and how many
    /// passes at it (counted only without sensors).
    private(set) var tempoStep = 0
    private var passesAtTempo = 0
    /// Scored passes at this speed that fell short of the next (sensors only).
    private var shortAtTempo = 0
    /// Strokes on the wrong bar in a row, in Step.
    private var wrongInARow = 0
    /// Waits for Step's held note to be struck, to say so if it is long.
    private var stuckTask: Task<Void, Never>?
    /// Scored play: the best pass so far this session, how many passes in a
    /// row went badly, and wrong-bar verdicts in a row.
    private var sessionBest = 0.0
    private var roughInARow = 0
    private var wrongVerdicts = 0

    /// What Kipli is saying over Learn's waterfall, and how he feels about
    /// it. Each step opens with what it asks; then he answers how it goes.
    private(set) var kipli: (line: LocalizedStringResource, mood: KipliGuide.Mood)?
    /// Between `setup` and `teardown`. Teardown runs twice on the way to the
    /// next step — called before moving on, then from `onDisappear` — and the
    /// second `cue.stop()` would land after the next step had started the
    /// same cue player, and silence it (see `ChooseKotekanViewModel.stopPreview`).
    private var live = false

    var paused = false
    /// 3, 2, 1 between pressing Resume and the clock running again — nil
    /// otherwise. Resuming straight away dropped the player back into a
    /// falling figure with their hands still off the bilah.
    private(set) var resumeCount: Int?
    private var resumeTask: Task<Void, Never>?
    private var pauseStartedAt: Double = 0
    /// Flat (top-down) or tilted towards the player. Remembered, because the
    /// view you like is the one you want next time.
    var tilted: Bool = Defaults.bool("waterfallTilted", false) {
        didSet { UserDefaults.standard.set(tilted, forKey: "waterfallTilted") }
    }

    /// Voice commands, for when both hands are on the panggul. Off until
    /// turned on from the pause screen — it asks for the microphone, and the
    /// question should come from a tap on the mic, not from opening a pattern.
    var voiceOn: Bool = Defaults.bool("voiceCommands", false) {
        didSet {
            Defaults.set("voiceCommands", voiceOn)
            if voiceOn { voice.start() } else { voice.stop() }
        }
    }

    /// What was heard and done — "Slower · 0.75×" — for a moment under the
    /// title, so a misheard command is seen and can be undone.
    private(set) var voiceCaption: String?
    private var captionTask: Task<Void, Never>?

    init(
        app: AppState,
        cue: CuePlayer = Container.shared.cueService(),
        sensor: GangsaSensor = Container.shared.sensorService()
    ) {
        self.app = app
        self.cue = cue
        self.sensor = sensor
        lesson = app.learnStage
    }

    // MARK: - Derived

    var title: String {
        let name = app.selectedKotekan?.name ?? ""
        return "\(name) · \(app.chosenHalf.title) · \(Theme.tempoLabel(app.tempoScale))"
    }

    var keyCount: Int {
        max(1, app.profile.keys.count)
    }

    /// The bilah the figure touches — drawn at full strength; the rest dim.
    var voicedKeys: ClosedRange<Int> {
        app.selectedKotekan?.voicedKeyRange ?? 0 ... keyCount - 1
    }

    /// Controller input → key, from this gangsa's own map (§3.6.5); nil is an
    /// input with no key on it, and its hits are dropped.
    ///
    /// The prototype wiring (three sensors on the lowest three bilah, any
    /// controller in reach) is gone from here: it let a gangsa with no
    /// controller borrow the one set up on another and be scored.
    func key(forInput input: Int) -> Int? {
        app.profile.keyForInput[input]
    }

    /// Sensors are optional, and without them nothing hears your strokes — so
    /// nothing is scored, and no hit or miss is drawn. Only THIS gangsa's
    /// controller counts (Settings → Strike controller); one set up on another
    /// gangsa does not, even when it is in reach.
    var sensing: Bool {
        app.controllerConnected
    }

    /// Whether the sensors were ever up this session. Never, and there is no
    /// result to show — End goes back to the picker, not to a 0%.
    private(set) var everSensed = false

    /// The bar a sensor just fired on, before any judging — so a dead piezo is
    /// obvious on the drawn gangsa.
    func sensedStrike(now: Double) -> (key: Int, age: Double)? {
        guard let hit = sensor.hits.first, now - hit.hostTime < 0.2,
              let key = key(forInput: hit.input) else { return nil }
        return (key, max(0, now - hit.hostTime))
    }

    // MARK: - Lifecycle

    func setup() {
        live = true
        engine.cue = cue
        engine.partnerAudible = lesson.map { $0.half == .sangsih } ?? app.partnerAudible
        engine.yourVoiceAudible = switch lesson {
        case .listen: true
        // Your stroke sounds when you make it: the real bar, or the sample on a tap.
        case .step: false
        default: app.yourVoiceAudible
        }
        engine.waitsForEachNote = isStep
        engine.onComplete = { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.teardown()
                if self.lesson != nil {
                    // Nothing in Learn is filed; quitting it is leaving it.
                    self.app.exitLearn()
                } else if let result, self.everSensed {
                    self.app.finish(result: result)
                } else {
                    self.app.backToKotekan()
                }
            }
        }
        configureEngine()
        everSensed = sensing
        kipli = opening(lesson)
        app.justLearned = false

        sensor.onHit = { [weak self] hit in
            guard let self, !self.paused, let key = key(forInput: hit.input) else { return }
            if isStep, let held = engine.heldKey { stepStruck(right: key == held) }
            engine.registerStrike(keyIndex: key, hostTime: hit.hostTime, confidence: 1)
        }
        // RootView follows this gangsa's controller, if it has one
        // (`AppState.sensorTarget`).

        // No microphone here, so none of the route-change race `PlayViewModel`
        // waits out before starting the cue engine — the clock can start now.
        engine.start()
        displayLink.onFrame = { [weak self] now in self?.engine.tick(now: now) }
        displayLink.start()

        voice.onCommand = { [weak self] in self?.heard($0) }
        if voiceOn { voice.start() }
    }

    /// From the top of the figure, count-in and all — setup's half, and
    /// Restart's whole.
    private func configureEngine() {
        guard let song = app.selectedSong else { return }
        engine.sessionSubtitle = title
        engine.configure(
            song: song,
            partner: app.partnerSong,
            profile: app.profile,
            tempoScale: lessonTempo ?? app.tempoScale,
            judging: sensing && (lesson == nil || isBuildUp),
            // Step waits on each note anyway; a count-in would only delay
            // the first wait.
            countIn: !isStep
        )
    }

    func teardown() {
        stuckTask?.cancel()
        guard live else { return }
        live = false
        resumeTask?.cancel()
        displayLink.stop()
        sensor.onHit = nil
        voice.onCommand = nil
        voice.stop()
        captionTask?.cancel()
        // Not `use(.none)`: RootView hands the controller back to the active
        // gangsa as this screen goes, and may already have.
        cue.stop()
    }

    // MARK: - Controls

    func pause() {
        guard !paused, !engine.isFinished else { return }
        paused = true
        pauseStartedAt = CACurrentMediaTime()
        displayLink.stop()
        cue.stopKeySamples()
    }

    /// Count 3, 2, 1, then run. Still paused while it counts — the countdown
    /// is part of the pause, so `resumeAfterPause` shifts the clock past it.
    func resume() {
        guard paused, resumeCount == nil else { return }
        resumeTask = Task { [weak self] in
            for n in [3, 2, 1] {
                self?.resumeCount = n
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self?.finishResume()
        }
    }

    private func finishResume() {
        resumeCount = nil
        guard paused else { return }
        engine.resumeAfterPause(seconds: CACurrentMediaTime() - pauseStartedAt)
        displayLink.start()
        paused = false
    }

    /// Backgrounded mid-count: stay paused, and ask for Resume again.
    private func cancelResume() {
        resumeTask?.cancel()
        resumeTask = nil
        resumeCount = nil
    }

    func end() {
        cancelResume()
        displayLink.stop()
        engine.end()
    }

    /// The figure again from its count-in, the session's scores with it — a
    /// Build up starts back at its slowest.
    func restart() {
        guard live, !engine.isFinished else { return }
        cancelResume()
        paused = false
        tempoStep = 0
        passesAtTempo = 0
        cue.stopKeySamples()
        configureEngine()
        engine.start()
        displayLink.start()
    }

    func sensingChanged(_ on: Bool) {
        // Listen and Step score nothing, sensors or not.
        if lesson == nil || isBuildUp { engine.setJudging(on) }
        if on { everSensed = true }
    }

    func halfChanged() {
        guard let song = app.selectedSong else { return }
        engine.sessionSubtitle = title
        engine.setHalf(song: song, partner: app.partnerSong)
    }

    func tempoChanged(_ scale: Double) {
        // Tempo is set from the pause screen now. The clock is frozen at the
        // moment of pausing, so anchor the change there: anchored to "now",
        // `resumeAfterPause` then added the whole pause on top and the
        // playhead jumped back by however long the menu took.
        engine.setTempoScale(scale, now: paused ? pauseStartedAt : CACurrentMediaTime())
        engine.sessionSubtitle = title
    }

    // MARK: - Learn

    private var isStep: Bool {
        if case .step = lesson { true } else { false }
    }

    private var isBuildUp: Bool {
        if case .buildUp = lesson { true } else { false }
    }

    /// Listen is the figure as written; Step moves at half speed between its
    /// waits; Build up starts at the bottom of its climb.
    private var lessonTempo: Double? {
        switch lesson {
        case .listen: 1
        case .step: 0.5
        case .buildUp: LearnStage.buildUpTempos[tempoStep]
        case .watch, nil: nil
        }
    }

    /// The line under the strip: what to do, and in Build up how far up.
    /// Each Build up line is one whole literal rather than the tempo `+` a
    /// tail: a translator has to see the sentence to reorder it.
    var lessonCaption: LocalizedStringKey? {
        switch lesson {
        case .listen: "Hear your part once, or tap Next"
        case .step: sensing ? "Strike the lit bar, or tap for the next note" : "Tap for the next note"
        case .buildUp:
            engine.judging
                ? "\(buildUpTempoLabel) · a pass at \(Int(LearnStage.accuracyToSpeedUp * 100))% to go faster"
                : "\(buildUpTempoLabel) · pass \(passesAtTempo + 1) of \(LearnStage.passesPerTempoUnsensed)"
        case .watch, nil: nil
        }
    }

    private var buildUpTempoLabel: String {
        Theme.tempoLabel(LearnStage.buildUpTempos[tempoStep])
    }

    /// The figure came round. Listen is one pass; Build up decides here
    /// whether the pass just finished earns the next speed.
    func loopChanged() {
        guard engine.phase == .userTurn, engine.loopIndex > 0 else { return }
        switch lesson {
        case nil:
            if engine.judging, let last = engine.lastClosedCycle, last.index == engine.loopIndex - 1 {
                judged(last.accuracy)
            }
        case .listen:
            nextStep()
        case .buildUp:
            if engine.judging {
                guard let last = engine.lastClosedCycle, last.index == engine.loopIndex - 1 else { return }
                guard last.accuracy >= LearnStage.accuracyToSpeedUp else { return fellShort(last.accuracy) }
            } else {
                passesAtTempo += 1
                guard passesAtTempo >= LearnStage.passesPerTempoUnsensed else { return }
            }
            speedUp()
        default:
            break
        }
    }

    private func speedUp() {
        passesAtTempo = 0
        shortAtTempo = 0
        guard tempoStep + 1 < LearnStage.buildUpTempos.count else { return nextStep() }
        tempoStep += 1
        kipli = ("Nice! A little faster now.", .happy)
        // On the turn of the cycle, so the pass just begun is all at the new
        // speed and counts.
        engine.setTempoScale(LearnStage.buildUpTempos[tempoStep], voidsPass: false)
    }

    // MARK: - Kipli

    /// What a step asks, in his words, as it opens — or, in free play, a
    /// cheer, or that Learn has just been finished.
    private func opening(_ lesson: LearnStage?) -> (line: LocalizedStringResource, mood: KipliGuide.Mood)? {
        switch lesson {
        case nil:
            app.justLearned
                ? ("You learned it! Now play it your way.", .happy)
                : ("Play along. I'll cheer you on.", .happy)
        case .listen(.polos): ("First just listen to polos. Watch where each note lands.", .happy)
        case .listen(.sangsih): ("Now sangsih. Hear how it fills the gaps polos leaves.", .happy)
        case .step:
            sensing
                ? ("Strike the lit bar. I'll wait for you.", .happy)
                : ("Tap for each note. I'll wait for you.", .happy)
        case .buildUp: ("Let's bring it up to speed, a little at a time.", .happy)
        case .watch: nil
        }
    }

    /// A scored Build up pass short of the next speed: close, he cheers you
    /// on; well off, or stuck at this speed, he is sad with you. A new line
    /// each time, so the bubble opens again for it.
    private func fellShort(_ accuracy: Double) {
        shortAtTempo += 1
        kipli = switch shortAtTempo {
        case 1 where accuracy >= 0.5: ("So close! One more clean pass.", .happy)
        case 1: ("Not quite yet. Again at this speed.", .sad)
        case 2: ("Hmm, still not there. Watch the lit bars.", .sad)
        default: ("Take a breath. Slow hands make fast hands.", .sad)
        }
    }

    /// Step: three strokes on the wrong bar in a row and he is cross; the
    /// right one after that and he is pleased again.
    private func stepStruck(right: Bool) {
        if right {
            if wrongInARow >= 3 { kipli = ("That's the one!", .happy) }
            wrongInARow = 0
        } else {
            wrongInARow += 1
            if wrongInARow == 3 { kipli = ("Hey, that's not the lit bar! Look for the glow.", .angry) }
        }
    }

    /// Step held a note: if it is still held a while later, he says to take
    /// your time — not cross, sad with you that it is hard.
    func heldChanged() {
        stuckTask?.cancel()
        guard isStep, let held = engine.heldKey else { return }
        stuckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled, !paused, engine.heldKey == held else { return }
            kipli = sensing
                ? ("Take your time. Find the lit bar.", .sad)
                : ("Take your time. Tap when you're ready.", .sad)
        }
    }

    /// Free play, a scored pass just closed: a best of the session he cheers
    /// (from the second pass — the first is always a best); three bad ones
    /// in a row and he is sad with you.
    private func judged(_ accuracy: Double) {
        let first = engine.loopIndex <= 1
        if accuracy < 0.5 {
            roughInARow += 1
            if roughInARow == 3 {
                kipli = ("That's a rough patch. Try it slower from the pause menu.", .sad)
            }
        } else {
            if roughInARow >= 3 { kipli = ("There it is. Back on track!", .happy) }
            roughInARow = 0
        }
        if accuracy > sessionBest {
            if !first, accuracy >= 0.6 {
                kipli = ("New best this session: \(Theme.percentLabel(accuracy))!", .happy)
            }
            sessionBest = accuracy
        }
    }

    /// A verdict floated up (scored play, not Step): three wrong bars in a
    /// row and he is cross; a hit after that and he is pleased again.
    func floated() {
        guard !isStep, let label = engine.floaters.last?.label else { return }
        switch label {
        case .wrongKey:
            wrongVerdicts += 1
            if wrongVerdicts == 3 { kipli = ("Whoa, wrong bars! Eyes on the lanes.", .angry) }
        case .perfect, .goodEarly, .goodLate:
            if wrongVerdicts >= 3 { kipli = ("That's more like it!", .happy) }
            wrongVerdicts = 0
        case .late, .miss, .unmatched:
            break
        }
    }

    /// A tap during Step lets the held note go; anywhere else it pauses —
    /// except over the opening count-in, which is already a countdown:
    /// paused there, Resume's 3, 2, 1 ran into it and there were two.
    func tapped() {
        if isStep, engine.heldKey != nil {
            engine.releaseStep()
        } else if engine.msUntilFirstNote == nil {
            pause()
        }
    }

    func stepsDone() {
        if engine.stepsDone { nextStep() }
    }

    /// On to the next step — torn down first, see `live`.
    func nextStep() {
        cancelResume()
        teardown()
        app.advanceLearn()
    }

    func skipLearn() {
        cancelResume()
        teardown()
        app.skipLearn()
    }

    /// From free play's pause screen: this pattern's Learn, from the top.
    func learnAgain() {
        guard let k = app.selectedKotekan else { return }
        cancelResume()
        teardown()
        app.startLearn(k, fromStart: true)
    }

    // MARK: - Voice

    private func heard(_ command: VoiceCommand) {
        guard live, !engine.isFinished else { return }
        switch command {
        case .slower, .faster, .normalSpeed:
            // A Learn step sets its own speed; Build up's climb is the point.
            guard lesson == nil else { return say(command, String(localized: "the step sets the speed")) }
            let scales = Theme.tempoScales
            let i = scales.firstIndex(of: app.tempoScale) ?? scales.firstIndex(of: 1) ?? 0
            let next = switch command {
            case .slower: scales[max(0, i - 1)]
            case .faster: scales[min(scales.count - 1, i + 1)]
            default: 1.0
            }
            app.tempoScale = next
            say(command, Theme.tempoLabel(next))
        case let .half(half):
            guard lesson == nil else { return say(command, String(localized: "the step sets your half")) }
            app.setHalf(half)
            say(command, String(localized: "you play \(half.title.lowercased())"))
        case .switchHalf:
            guard lesson == nil else { return say(command, String(localized: "the step sets your half")) }
            app.setHalf(app.chosenHalf.other)
            say(command, String(localized: "you play \(app.chosenHalf.title.lowercased())"))
        case .pause:
            // Not over the opening count-in, for the same reason a tap does not.
            guard !paused, engine.msUntilFirstNote == nil else { return }
            pause()
            say(command, nil)
        case .resume:
            guard paused, resumeCount == nil else { return }
            resume()
            say(command, nil)
        case .end:
            say(command, nil)
            end()
        case .restart:
            restart()
            say(command, nil)
        case .next:
            if isStep, engine.heldKey != nil {
                engine.releaseStep()
            } else if lesson != nil {
                nextStep()
            } else {
                return
            }
            say(command, nil)
        }
    }

    private func say(_ command: VoiceCommand, _ detail: String?) {
        voiceCaption = ["“\(command.title)”", detail].compactMap(\.self).joined(separator: " · ")
        captionTask?.cancel()
        captionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.voiceCaption = nil
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        guard phase != .active else { return }
        cancelResume()
        pause()
    }
}

//
//  PlayViewModel.swift
//  Kotek
//
//  ViewModel coordinating the real-time practice session (vision, audio, cues, tour, display link).
//

import CoreGraphics
import FactoryKit
import Foundation
import Observation
import QuartzCore
import SwiftUI

@Observable
@MainActor
final class PlayViewModel {
    let app: AppState
    let camera: CameraController
    let audio: AudioEngineController
    let cue: CuePlayer

    let engine = PlayEngine()
    private let displayLink = DisplayLink()
    private var fusion: StrikeFusion?
    private var visionDetector = VisionStrikeDetector()

    var overlaySize: CGSize = .zero
    var startCue: StartCue? = .getReady
    var paused: Bool = false
    var coachStep: CoachStep?
    private var coachStartsSession = false
    private var panelWasVisible = false
    private var pauseStartedAt: Double = 0

    private var lastKey: Int?
    private var lastConfidence: Double = 0
    private var unclearAt: Double?

    private let visionTeachingConfidence: Double = 0.75

    init(
        app: AppState,
        camera: CameraController = Container.shared.cameraService(),
        audio: AudioEngineController = Container.shared.audioService(),
        cue: CuePlayer = Container.shared.cueService()
    ) {
        self.app = app
        self.camera = camera
        self.audio = audio
        self.cue = cue
    }

    // MARK: - Computed Properties

    var sessionTitle: String {
        app.selectedKotekan?.name ?? ""
    }

    var record: Double? {
        guard let k = app.selectedKotekan else { return nil }
        return app.profile.record(
            kotekanId: k.id,
            half: app.chosenHalf.rawValue,
            tempo: app.tempoScale
        )?.accuracy
    }

    var sessionSubtitle: String {
        let name = app.selectedKotekan?.name ?? ""
        return "\(name) · \(app.chosenHalf.title) · \(Theme.tempoLabel(app.tempoScale))"
    }

    var keyRange: ClosedRange<Int> {
        app.selectedKotekan?.voicedKeyRange
            ?? 0 ... max(0, app.profile.keys.count - 1)
    }

    var playedKeys: Set<Int> {
        guard let k = app.selectedKotekan else { return [] }
        return Set(k.pattern(app.chosenHalf).compactMap { $0 })
    }

    // MARK: - Lifecycle

    func setup() {
        camera.wantsFrames = true
        camera.start()
        if app.fixedMount {
            camera.lockFocusAndExposure()
        } else {
            camera.enableContinuousAutoFocus()
        }

        engine.cue = cue
        engine.leniency = app.judgementLeniency
        engine.callsStrokes = app.callsStrokes
        engine.scoresWrongBar = app.scoresWrongBar
        engine.metronomeEnabled = app.metronomeEnabled
        engine.referenceToneEnabled = app.referenceToneEnabled
        engine.sessionSubtitle = sessionSubtitle
        engine.onComplete = { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.teardown()
                if let result {
                    self.app.finish(result: result)
                } else {
                    self.app.backToKotekan()
                }
            }
        }

        engine.partnerAudible = app.partnerAudible
        engine.yourVoiceAudible = app.yourVoiceAudible
        if let song = app.selectedSong {
            engine.configure(
                song: song,
                partner: app.partnerSong,
                profile: app.profile,
                tempoScale: app.tempoScale
            )
        }

        let fusion = StrikeFusion(
            frames: camera.frameBuffer,
            keys: app.profile.keys,
            viewSize: overlaySize
        )
        self.fusion = fusion

        let active = playedKeys
        Task {
            await fusion.setActiveKeys(active)
            await fusion.setMinHitProbability(
                Detection.namingThreshold(from: self.app.visionThreshold)
            )
        }

        visionDetector.reset()
        visionDetector.apply(
            threshold: app.visionThreshold,
            relativeDip: app.visionRelativeDip
        )
        try? audio.start(profile: app.profile)
        audio.resetDetector()
        audio.setKeyOpinionsEnabled(true)
        audio.setDecompositionKeys(active)
        if let baseline = app.profile.strikeBaseline {
            audio.setBaselineTemplate(baseline)
        }

        audio.onStrikeDetected = { [weak self] hostTime in
            Task { @MainActor in
                guard let self, self.startCue == nil, !self.paused, !self.engine.isFinished else {
                    return
                }
                if let decision = await self.fusion?.resolveVisionFirst(hostTime: hostTime) {
                    self.applyStrike(
                        key: decision.keyIndex,
                        hostTime: hostTime,
                        confidence: decision.hitProbability
                    )
                    self.audio.noteVisionDecision(
                        decision.keyIndex,
                        confidence: decision.hitProbability,
                        at: hostTime
                    )
                    if decision.hitProbability >= self.visionTeachingConfidence {
                        self.audio.learnKey(decision.keyIndex, at: hostTime)
                    }
                } else if self.app.audioTriggersStrikes,
                          let heard = self.audio.keyOpinion(at: hostTime)
                {
                    self.audio.noteRecovery()
                    self.applyStrike(
                        key: heard.keyIndex,
                        hostTime: hostTime,
                        confidence: Double(heard.share)
                    )
                }
            }
        }

        if app.hasSeenPracticeCoach {
            runCountdown()
        } else {
            startCoach(startsSession: true)
        }
    }

    func teardown() {
        displayLink.stop()
        audio.onStrikeDetected = nil
        audio.onConfirmedStrike = nil

        audio.learnedAtoms { [weak self] templates in
            guard let self, !templates.isEmpty else { return }
            app.storeLinearTemplates(templates)
        }
        audio.setKeyOpinionsEnabled(false)
        audio.stop()
        cue.stop()
    }

    // MARK: - Coach Tour

    func startCoach(startsSession: Bool, from first: CoachStep = .session) {
        coachStartsSession = startsSession
        panelWasVisible = app.bottomBarVisible
        withAnimation(.easeInOut(duration: 0.2)) {
            if first.needsPanel { app.bottomBarVisible = true }
            coachStep = first
        }
    }

    func advanceCoach() {
        guard let coachStep else { return }
        guard let next = CoachStep(rawValue: coachStep.rawValue + 1) else {
            finishCoach()
            return
        }
        withAnimation(.easeInOut(duration: 0.24)) {
            if next.needsPanel { app.bottomBarVisible = true }
            self.coachStep = next
        }
    }

    func finishCoach() {
        app.markPracticeCoachSeen()
        withAnimation(.easeInOut(duration: 0.24)) {
            app.bottomBarVisible = panelWasVisible
            coachStep = nil
        }
        if coachStartsSession { runCountdown() }
    }

    // MARK: - Countdown & DisplayLink

    func runCountdown() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            engine.start()
            startDisplayLink()
        }
    }

    private func startDisplayLink() {
        displayLink.onFrame = { [weak self] now in
            guard let self else { return }
            engine.tick(now: now)

            let next: StartCue? =
                engine.msUntilFirstNote == nil
                    ? nil
                    : engine.countdownNumber.map(StartCue.count) ?? .getReady

            guard next != startCue else { return }
            startCue = next
            if next == nil { app.countdownFinished() }
        }
        displayLink.start()
    }

    // MARK: - Vision Loop

    func runVisionDetection() async {
        while !Task.isCancelled {
            if !app.audioTriggersStrikes,
               startCue == nil, !paused, !engine.isFinished,
               let (scores, hostTime) = await fusion?.latestScores()
            {
                let fired = visionDetector.process(
                    scores: scores,
                    expecting: engine.dueKey,
                    now: hostTime
                )
                if let key = fired.max(by: { (scores[$0] ?? 0) < (scores[$1] ?? 0) }) {
                    let onset = audio.nearestOnset(
                        to: hostTime,
                        within: Detection.corroborationWindow
                    )
                    if app.requireStrikeSound, onset == nil { continue }
                    applyStrike(
                        key: key,
                        hostTime: onset ?? hostTime,
                        confidence: scores[key] ?? 1
                    )
                }
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func applyStrike(key: Int, hostTime: Double, confidence: Double) {
        lastKey = key
        lastConfidence = confidence
        unclearAt = nil
        engine.registerStrike(
            keyIndex: key,
            hostTime: hostTime,
            confidence: confidence
        )
    }

    // MARK: - Session Control

    func pause() {
        guard startCue == nil, !paused, !engine.isFinished else { return }
        paused = true
        pauseStartedAt = CACurrentMediaTime()
        displayLink.stop()
        audio.stop()
    }

    func resume() {
        guard paused else { return }
        engine.resumeAfterPause(seconds: CACurrentMediaTime() - pauseStartedAt)
        try? audio.start(profile: app.profile)
        audio.resetDetector()
        visionDetector.reset()
        displayLink.start()
        paused = false
    }

    func endPractice() {
        guard startCue == nil, !paused else { return }
        displayLink.stop()
        engine.end()
    }

    // MARK: - Change Handlers

    func handleChosenHalfChanged() {
        guard let song = app.selectedSong else { return }
        engine.sessionSubtitle = sessionSubtitle
        engine.setHalf(song: song, partner: app.partnerSong)
        let active = playedKeys
        Task { await fusion?.setActiveKeys(active) }
        audio.setDecompositionKeys(active)
    }

    func handleTempoScaleChanged(_ newScale: Double) {
        engine.setTempoScale(newScale)
        engine.sessionSubtitle = sessionSubtitle
    }

    func handleOverlaySizeChanged(_ newSize: CGSize) {
        overlaySize = newSize
        Task { await fusion?.setViewSize(newSize) }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        if phase != .active { pause() }
    }
}

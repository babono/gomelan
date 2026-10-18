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

    var paused = false
    private var pauseStartedAt: Double = 0
    /// Flat (top-down) or tilted towards the player. Remembered, because the
    /// view you like is the one you want next time.
    var tilted: Bool = Defaults.bool("waterfallTilted", false) {
        didSet { UserDefaults.standard.set(tilted, forKey: "waterfallTilted") }
    }

    init(
        app: AppState,
        cue: CuePlayer = Container.shared.cueService(),
        sensor: GangsaSensor = Container.shared.sensorService()
    ) {
        self.app = app
        self.cue = cue
        self.sensor = sensor
    }

    // MARK: - Derived

    var title: String {
        let name = app.selectedKotekan?.name ?? ""
        return "\(name) · \(app.chosenHalf.title) · \(Theme.tempoLabel(app.tempoScale))"
    }

    var record: Double? {
        guard let k = app.selectedKotekan else { return nil }
        return app.profile.record(
            kotekanId: k.id,
            half: app.chosenHalf.rawValue,
            tempo: app.tempoScale
        )?.accuracy
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
        engine.cue = cue
        engine.leniency = app.judgementLeniency
        engine.callsStrokes = app.callsStrokes
        engine.scoresWrongBar = app.scoresWrongBar
        engine.partnerAudible = app.partnerAudible
        engine.yourVoiceAudible = app.yourVoiceAudible
        engine.sessionSubtitle = title
        engine.onComplete = { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.teardown()
                if let result, self.everSensed {
                    self.app.finish(result: result)
                } else {
                    self.app.backToKotekan()
                }
            }
        }
        if let song = app.selectedSong {
            engine.configure(
                song: song,
                partner: app.partnerSong,
                profile: app.profile,
                tempoScale: app.tempoScale,
                judging: sensing
            )
        }
        everSensed = sensing

        sensor.onHit = { [weak self] hit in
            guard let self, !self.paused, let key = key(forInput: hit.input) else { return }
            engine.registerStrike(keyIndex: key, hostTime: hit.hostTime, confidence: 1)
        }
        // RootView follows this gangsa's controller, if it has one
        // (`AppState.sensorTarget`).

        // No microphone here, so none of the route-change race `PlayViewModel`
        // waits out before starting the cue engine — the clock can start now.
        engine.start()
        displayLink.onFrame = { [weak self] now in self?.engine.tick(now: now) }
        displayLink.start()
    }

    func teardown() {
        displayLink.stop()
        sensor.onHit = nil
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

    func resume() {
        guard paused else { return }
        engine.resumeAfterPause(seconds: CACurrentMediaTime() - pauseStartedAt)
        displayLink.start()
        paused = false
    }

    func end() {
        displayLink.stop()
        engine.end()
    }

    func leave() {
        teardown()
        app.backToKotekan()
    }

    func sensingChanged(_ on: Bool) {
        engine.setJudging(on)
        if on { everSensed = true }
    }

    func halfChanged() {
        guard let song = app.selectedSong else { return }
        engine.sessionSubtitle = title
        engine.setHalf(song: song, partner: app.partnerSong)
    }

    func tempoChanged(_ scale: Double) {
        engine.setTempoScale(scale)
        engine.sessionSubtitle = title
    }

    func handleScenePhase(_ phase: ScenePhase) {
        if phase != .active { pause() }
    }
}

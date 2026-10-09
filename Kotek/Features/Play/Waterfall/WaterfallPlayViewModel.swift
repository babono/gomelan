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

    init(app: AppState,
         cue: CuePlayer = Container.shared.cueService(),
         sensor: GangsaSensor = GangsaSensor()) {
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
        return app.profile.record(kotekanId: k.id, half: app.chosenHalf.rawValue,
                                  tempo: app.tempoScale)?.accuracy
    }

    var keyCount: Int { max(1, app.profile.keys.count) }

    /// The bilah the figure touches — drawn at full strength; the rest dim.
    var voicedKeys: ClosedRange<Int> {
        app.selectedKotekan?.voicedKeyRange ?? 0 ... keyCount - 1
    }

    /// Sensor bar → key. The three sensors sit on the lowest three bilah the
    /// figure uses.
    ///
    /// ponytail: fixed offset, three sensors. Becomes a per-instrument mapping
    /// in the profile once there is a sensor on every bar.
    func key(forBar bar: Int) -> Int {
        voicedKeys.lowerBound + bar
    }

    // MARK: - Lifecycle

    func setup() {
        engine.cue = cue
        engine.leniency = app.judgementLeniency
        engine.callsStrokes = app.callsStrokes
        engine.scoresWrongBar = app.scoresWrongBar
        engine.metronomeEnabled = app.metronomeEnabled
        engine.referenceToneEnabled = app.referenceToneEnabled
        engine.partnerAudible = app.partnerAudible
        engine.yourVoiceAudible = app.yourVoiceAudible
        engine.sessionSubtitle = title
        engine.onComplete = { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.teardown()
                if let result { self.app.finish(result: result) } else { self.app.backToKotekan() }
            }
        }
        if let song = app.selectedSong {
            engine.configure(song: song, partner: app.partnerSong,
                             profile: app.profile, tempoScale: app.tempoScale)
        }

        sensor.onHit = { [weak self] hit in
            guard let self, !self.paused else { return }
            self.engine.registerStrike(keyIndex: self.key(forBar: hit.bar),
                                       hostTime: hit.hostTime, confidence: 1)
        }
        sensor.start()

        // No microphone here, so none of the route-change race `PlayViewModel`
        // waits out before starting the cue engine — the clock can start now.
        engine.start()
        displayLink.onFrame = { [weak self] now in self?.engine.tick(now: now) }
        displayLink.start()
    }

    func teardown() {
        displayLink.stop()
        sensor.onHit = nil
        sensor.stop()
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

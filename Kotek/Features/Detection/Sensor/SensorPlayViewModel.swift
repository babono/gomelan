//
//  SensorPlayViewModel.swift
//  Kotek
//
//  ViewModel coordinating the piezo sensor test session.
//  Coordinates GangsaSensor BLE events, PlayEngine score simulation,
//  CADisplayLink frame ticks, and CuePlayer audio cues.
//

import FactoryKit
import Foundation
import Observation
import QuartzCore
import SwiftUI

@Observable
@MainActor
final class SensorPlayViewModel {
    // MARK: - Dependencies

    let cue: CuePlayer
    let sensor: GangsaSensor
    let engine: PlayEngine
    private let displayLink: DisplayLink

    // MARK: - State

    var half: KotekanHalf = .polos
    // Half speed by default: 250 ms a slot is a lot to ask while watching
    // whether a breadboard is keeping up.
    var tempo: Double = 0.5
    var running: Bool = false
    var lastResult: SongResult?

    let figure: Kotekan
    var keys: ClosedRange<Int> { figure.voicedKeyRange }

    // MARK: - Initialization

    init(
        cue: CuePlayer = Container.shared.cueService(),
        sensor: GangsaSensor? = nil,
        engine: PlayEngine? = nil,
        displayLink: DisplayLink? = nil
    ) {
        self.cue = cue
        self.sensor = sensor ?? GangsaSensor()
        self.engine = engine ?? PlayEngine()
        self.displayLink = displayLink ?? DisplayLink()
        self.figure = Kotekan.bundled.first { $0.id == "ubitannyendok" }!
    }

    func key(forBar bar: Int) -> Int {
        keys.lowerBound + bar
    }

    // MARK: - Lifecycle

    func onAppear() {
        sensor.onHit = { [weak self] hit in
            guard let self, self.running else { return }
            self.engine.registerStrike(
                keyIndex: self.key(forBar: hit.bar),
                hostTime: hit.hostTime,
                confidence: 1
            )
        }
        sensor.start()
    }

    func onDisappear() {
        stopSession()
        sensor.onHit = nil
        sensor.stop()
    }

    // MARK: - Actions

    func updateHalf(_ newHalf: KotekanHalf) {
        half = newHalf
        guard running else { return }
        engine.setHalf(
            song: figure.makeSong(half: newHalf, cycles: 1),
            partner: figure.makeSong(half: newHalf.other, cycles: 1)
        )
    }

    func updateTempo(_ newTempo: Double) {
        tempo = newTempo
        if running {
            engine.setTempoScale(newTempo)
        }
    }

    func toggleSession(app: AppState) {
        if running {
            stopSession()
        } else {
            startSession(app: app)
        }
    }

    func clearHits() {
        sensor.clearHits()
    }

    func startSession(app: AppState) {
        engine.cue = cue
        engine.leniency = app.judgementLeniency
        engine.callsStrokes = true
        engine.scoresWrongBar = app.scoresWrongBar
        engine.metronomeEnabled = app.metronomeEnabled
        engine.referenceToneEnabled = app.referenceToneEnabled
        // Partner on: you are playing one half of an interlocking figure, and
        // without the other half there is nothing to lock into.
        engine.partnerAudible = true
        engine.yourVoiceAudible = true
        engine.sessionSubtitle = "Sensor demo"
        // Results stay on this screen. Going through `app.finish` would file a
        // record against the real kotekan for a session played on a breadboard.
        engine.onComplete = { [weak self] result in
            Task { @MainActor in
                self?.lastResult = result
            }
        }
        engine.configure(
            song: figure.makeSong(half: half, cycles: 1),
            partner: figure.makeSong(half: half.other, cycles: 1),
            profile: app.profile,
            tempoScale: tempo
        )
        engine.start()
        displayLink.onFrame = { [weak self] now in
            self?.engine.tick(now: now)
        }
        displayLink.start()
        running = true
    }

    func stopSession() {
        guard running else { return }
        running = false
        displayLink.stop()
        engine.end()
        cue.stop()
    }
}

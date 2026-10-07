//
//  CalibrationViewModel.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import FactoryKit
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class CalibrationViewModel {
    private let app: AppState
    let camera: CameraController
    let audio: AudioEngineController

    /// Clean strikes needed to consider the voice learned.
    let strikesNeeded = 6

    var strikeCount = 0
    /// Whether the most recent strike was folded in or rejected as an outlier.
    var lastAccepted: Bool?
    /// Amplitude + time of the most recent strike, for the mic visualisation.
    var micLevel: Float = 0
    var micLevelTime: Double = 0
    var committing = false
    /// Up from the moment this screen appears until it is actually listening.
    var preparing = true

    var confidence: Double {
        min(1, Double(strikeCount) / Double(strikesNeeded))
    }

    var learned: Bool {
        strikeCount >= strikesNeeded
    }

    var busyMessage: String? {
        if preparing { return "Getting ready to listen…" }
        return committing ? "Learning the strike…" : nil
    }

    init(
        app: AppState,
        camera: CameraController = Container.shared.cameraService(),
        audio: AudioEngineController = Container.shared.audioService()
    ) {
        self.app = app
        self.camera = camera
        self.audio = audio
    }

    func start() {
        // Paint the scrim BEFORE setup runs: starting the audio engine
        // blocks for a moment, and a spinner that only appears afterwards
        // has missed the wait it was there for.
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            setup()
            // Hold while this screen's own camera preview warms up.
            try? await Task.sleep(for: .milliseconds(900))
            preparing = false
        }
    }

    private func setup() {
        camera.start()
        try? audio.start(profile: app.profile)
        audio.clearBaseline()
        audio.startBaselineCapture()
        // Pulse the visualisation on any loud onset…
        audio.onOnsetDebug = { [weak self] debug in
            Task { @MainActor [weak self] in
                guard debug.passedGate else { return }
                self?.micLevel = debug.amplitude
                self?.micLevelTime = debug.hostTime
            }
        }
        // …but let the engine decide which strikes actually count: it folds in
        // ones that resemble the template so far and rejects outliers.
        audio.onBaselineProgress = { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self else { return }
                strikeCount = progress.accepted
                withAnimation(.snappy(duration: 0.2)) {
                    self.lastAccepted = progress.wasAccepted
                }
            }
        }
    }

    func reset() {
        strikeCount = 0
        lastAccepted = nil
        audio.startBaselineCapture() // drops the old accumulator, starts fresh
    }

    func commit() {
        guard !committing else { return }
        committing = true
        audio.finishBaselineCapture { [weak self] _, template in
            guard let self else { return }
            if let template {
                var updated = app.profile
                updated.strikeBaseline = template
                app.profile = updated
                app.saveProfile()
            }
            app.baselineFinished()
        }
    }

    func cancel() {
        audio.onOnsetDebug = nil
        audio.onBaselineProgress = nil
        audio.clearBaseline()
        audio.stop()
        app.skipCalibration()
    }

    func teardown() {
        audio.onOnsetDebug = nil
        audio.onBaselineProgress = nil
        audio.stop()
    }
}

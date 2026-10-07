//
//  StrikeBaselineViewModel.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import FactoryKit
import Foundation
import Observation

@Observable
@MainActor
final class StrikeBaselineViewModel {
    private let app: AppState
    let camera: CameraController
    let audio: AudioEngineController

    var capturing = false
    /// nil until a capture has completed; then the number of strikes learned.
    var strikeCount: Int?
    var busyMessage: String?

    var statusText: String {
        if capturing { return "Keep striking the keys a few times…" }
        switch strikeCount {
        case .none:
            return "Strike any keys a few times so the app learns what a real gangsa strike sounds like."
        case .some(0):
            return "No strikes heard — tap Start and hit a few keys."
        case let .some(n):
            return "Learned from \(n) strike\(n == 1 ? "" : "s"). You can re-record or continue."
        }
    }

    var recordTitle: String {
        if capturing { return "Done" }
        return strikeCount == nil ? "Start listening" : "Re-record"
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

    func setup() {
        camera.start()
        try? audio.start(profile: app.profile)
    }

    func teardown() {
        if capturing { audio.finishBaselineCapture { _, _ in } }
        audio.stop()
    }

    func toggleCapture() {
        if capturing {
            busyMessage = "Learning the strike…"
            audio.finishBaselineCapture { [weak self] count, _ in
                guard let self else { return }
                strikeCount = count
                capturing = false
                busyMessage = nil
            }
        } else {
            audio.startBaselineCapture()
            capturing = true
        }
    }

    /// Leave for the song list. When a baseline was actually learned, turn the
    /// strike-sound gate on so it is used in play; skipping leaves vision-only
    /// (the more lenient default).
    func finish(enableGate: Bool) {
        guard busyMessage == nil else { return }
        if enableGate, audio.hasStrikeBaseline {
            app.requireStrikeSound = true
        }
        // The profile written here carries the baseline template, so it is no
        // longer a trivial file.
        busyMessage = "Saving the gangsa…"
        Task { [weak self] in
            guard let self else { return }
            await app.baselineFinishedAsync()
            busyMessage = nil
        }
    }
}

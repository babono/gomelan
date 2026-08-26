//
//  Preloader.swift
//  Kotek
//
//  Everything expensive the app needs later, done once at launch while the
//  splash screen is on screen.
//
//  The app had two visible pauses, both for the same reason: work that is
//  identical every time was being done at the moment it was first needed, on
//  the main actor, behind a screen that had already changed.
//
//   - Opening the camera. `AVCaptureSession` configuration plus
//     `startRunning()` is the better part of a second, and it was starting in
//     the framing screen's `onAppear` — so the player watched a black
//     rectangle.
//   - Starting a session. Thirteen WAVs decoded and scanned (SampleLibrary),
//     and a Core ML model compiled (MalletHitClassifier) — all on the way into
//     play.
//
//  None of it depends on anything the player does, so none of it has to wait
//  for them. The splash is not a stall dressed up as a screen: it is that work,
//  made visible.
//
//  What is deliberately NOT preloaded:
//
//   - The audio ENGINE (CuePlayer.start / AudioEngineController.start). Both
//     activate the shared `AVAudioSession` and one of them installs a
//     microphone tap. Doing that at launch would take the mic before the app
//     has asked for it, and would fight the title music on the welcome screen.
//     Only the sample DECODING — the slow part — is warmed here; wiring up the
//     graph is fast and stays where it belongs.
//   - Actually RUNNING the camera. The capture graph is built here, which is
//     the slow half; `startRunning()` stays with the screen that shows a
//     preview, so the recording indicator never lights over a screen with no
//     camera image on it.
//   - The camera at all, when permission has not been granted yet. Touching the
//     capture device would trigger the system prompt over the splash screen,
//     which is both ugly and the wrong place to ask. First launch therefore
//     warms what it can and configures the camera the old way, once; every
//     launch after that has it ready.
//

import SwiftUI
import Observation
import AVFoundation

@MainActor
@Observable
final class Preloader {
    /// 0…1, for the progress bar. Advances as each step lands rather than on a
    /// timer — the bar is reporting real work, not animating over it.
    private(set) var progress: Double = 0
    /// True once everything below has finished AND the floor time has elapsed.
    private(set) var isFinished = false

    /// The splash never shows for less than this.
    ///
    /// Not padding for its own sake, and not a guess. On a warm launch the work
    /// below finishes in well under a tenth of a second, so without a floor the
    /// splash would appear and vanish within a couple of frames — which reads as
    /// a rendering fault rather than as a screen.
    ///
    /// Two seconds specifically, because the splash has something to say: it
    /// carries the Mekar Bhuana credit, and a collaborator's name that cannot be
    /// read is not a credit. This is the one screen in the app whose duration is
    /// set by how long it takes to READ rather than by how long the work takes,
    /// so it does not shrink if the work ever gets faster.
    private let minimumDuration: Duration = .seconds(2)

    /// Each unit of work, weighted by roughly how long it takes, so the bar
    /// moves at a believable rate instead of jumping.
    private enum Step: CaseIterable {
        case samples, model, camera

        var weight: Double {
            switch self {
            case .samples: return 0.35   // 13 files, decode + two scans each
            case .model:   return 0.35   // Core ML compile + Vision wrapper
            case .camera:  return 0.30   // capture graph configuration
            }
        }
    }

    private var done: Set<Step> = []
    private var hasStarted = false

    /// Warm everything, then report finished.
    ///
    /// The three steps are independent, so they run concurrently — the camera
    /// spends most of its time waiting on hardware, which is time the decoder
    /// and the model loader may as well use.
    func warm(camera: CameraController) async {
        // SwiftUI re-runs a `.task` whenever the view's identity changes, and
        // running this twice would put the splash back over a running app.
        // Warming is idempotent, but the screen it drives is not.
        guard !hasStarted else { return }
        hasStarted = true

        let started = ContinuousClock.now

        await withTaskGroup(of: Step.self) { group in
            group.addTask {
                // Off the main actor: this is the arithmetic-heavy one.
                await Task.detached(priority: .userInitiated) {
                    for name in SampleLibrary.allNames {
                        _ = SampleLibrary.shared.buffer(name)
                    }
                }.value
                return .samples
            }

            group.addTask {
                await Task.detached(priority: .userInitiated) {
                    _ = MalletHitClassifier.shared()
                }.value
                return .model
            }

            // Read on the main actor, where it is isolated, rather than inside
            // the child task — the answer cannot change between here and there,
            // and reaching across for it is only legal by accident.
            let cameraIsOursToOpen = CameraController.cameraAuthorized
            group.addTask {
                // Only when the camera is already ours to open — see the note
                // at the top about the permission prompt.
                if cameraIsOursToOpen {
                    await camera.prepare()
                }
                return .camera
            }

            for await step in group {
                done.insert(step)
                withAnimation(.easeOut(duration: 0.35)) {
                    progress = Step.allCases
                        .filter { done.contains($0) }
                        .reduce(0) { $0 + $1.weight }
                }
            }
        }

        // The kajar under every button press. Cheap — it shortens and re-encodes
        // one already-decoded sample and prepares four players — but it is main-
        // actor work, and the first thing anyone taps is the button on the very
        // next screen. Doing it here means that first tick is not the one that
        // arrives late.
        KajarTick.shared.warm()

        // Hold the floor, measured from when warming began rather than from
        // here, so the wait is only ever the REMAINDER of the minimum — a slow
        // warm-up on a cold launch costs nothing extra, and a fast one still
        // gets a splash long enough to read as one.
        let remaining = minimumDuration - started.duration(to: .now)
        if remaining > .zero { try? await Task.sleep(for: remaining) }

        withAnimation(.easeOut(duration: 0.25)) { progress = 1 }
        isFinished = true
    }
}

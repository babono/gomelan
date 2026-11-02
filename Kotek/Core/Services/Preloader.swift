//
//  Preloader.swift
//  Kotek
//
//  Everything expensive the app needs later, done once at launch while the
//  splash screen is on screen.
//
//  Starting a session used to pause visibly: thirteen WAVs decoded and
//  scanned (SampleLibrary) on the main actor, on the way into play, behind a
//  screen that had already changed. It was one of two such pauses; the other
//  — opening the camera, and compiling the mallet detector's Core ML model —
//  went with the camera play mode in November 2026.
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
//

import Observation
import SwiftUI

@MainActor
@Observable
final class Preloader {
    /// True once everything below has finished AND the floor time has elapsed.
    private(set) var isFinished = false

    /// The splash never shows for less than this.
    ///
    /// On a warm launch the work below finishes in well under a tenth of a
    /// second, so without a floor the splash would appear and vanish within a
    /// couple of frames — which reads as a rendering fault rather than as a
    /// screen. A second and a half is three of Kipli's chomps.
    ///
    /// It was the shortest of three timers. A progress bar under Kipli was
    /// paced across the screen — 11% for a second, 67% for two, then full and
    /// held for one more so it read as finished — and on a warm launch those
    /// pauses, not the work, were the splash's length: over four seconds of a
    /// bar pretending. The bar went (November 2026), and its pacing with it;
    /// Kipli chomping and the rose turning say the app is alive on their own.
    private let minimumDuration: Duration = .milliseconds(1500)

    private var hasStarted = false

    /// Warm everything, then report finished.
    func warm() async {
        // SwiftUI re-runs a `.task` whenever the view's identity changes, and
        // running this twice would put the splash back over a running app.
        // Warming is idempotent, but the screen it drives is not.
        guard !hasStarted else { return }
        hasStarted = true

        let started = ContinuousClock.now

        // Off the main actor: this is the arithmetic-heavy one.
        await Task.detached(priority: .userInitiated) {
            for name in SampleLibrary.allNames {
                _ = SampleLibrary.shared.buffer(name)
            }
        }.value

        // The kajar under every button press. Cheap — it shortens and re-encodes
        // one already-decoded sample and prepares four players — but it is main-
        // actor work, and the first thing anyone taps is the button on the very
        // next screen. Doing it here means that first tick is not the one that
        // arrives late.
        await KajarTick.warm()

        // Hold the floor, measured from when warming began rather than from
        // here, so the wait is only ever the REMAINDER of the minimum — a slow
        // warm-up on a cold launch costs nothing extra, and a fast one still
        // gets a splash long enough to read as one.
        let remaining = minimumDuration - started.duration(to: .now)
        if remaining > .zero { try? await Task.sleep(for: remaining) }

        isFinished = true
    }
}

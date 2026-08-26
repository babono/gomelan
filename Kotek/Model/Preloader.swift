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
    /// 0…1, for the progress bar. What has actually landed, held between the
    /// bounds of whichever `Stop` the bar is currently at — see `stops`.
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
    /// It is now the SHORTER of the two things setting the splash's length —
    /// `stops` dwells for three seconds and `fullDwell` for another — and it
    /// stays as the guarantee rather than the schedule: whatever the bar is
    /// doing, the screen is up for at least this long.
    private let minimumDuration: Duration = .seconds(2)

    /// How long the bar sits full before the splash hands over.
    ///
    /// Not one of the `stops`, and it cannot be: those are ceilings the pacer
    /// walks BESIDE the work, and a dwell at 100% that could elapse while the
    /// work was still running would be a lie. This one is at the tail, after
    /// everything has actually finished.
    ///
    /// The bar takes a quarter-second to reach full, so this leaves about
    /// three-quarters of a second of it visibly complete. A bar that hits 100%
    /// and vanishes in the same frame never reads as having finished — it reads
    /// as having been interrupted, which is a strange last impression for a
    /// screen whose whole job is to say the work is done.
    private let fullDwell: Duration = .seconds(1)

    /// Where the bar stops on its way across, and how long it sits there.
    ///
    /// On a warm launch all three steps land within a couple of frames of each
    /// other, so left alone the bar goes from nothing to full in one animation
    /// and the screen behind it never registers — the floor holds the SCREEN for
    /// two seconds, but the bar has finished moving inside the first quarter of
    /// one, which reads as a picture rather than as loading.
    ///
    /// So the crossing is paced. Eleven percent for a second out of the gate,
    /// then two seconds at sixty-seven, then away. Neither number is round on
    /// purpose: a bar resting on 10 or 70 looks like a placeholder, and eleven
    /// percent of a pill this size is just past the readout, so the fill is
    /// visibly somewhere rather than visibly nowhere.
    ///
    /// A stop is a CEILING, not a script. The bar still shows what has actually
    /// landed — it simply will not report past the current stop until the dwell
    /// is over, and will not fall below the one before it. On a warm launch the
    /// work is finished before the first dwell ends, so the ceilings are all
    /// anyone ever sees and the crossing is 11 → 67 → 100. On a cold one the bar
    /// climbs through the middle stop under its own steam and the dwell is spent
    /// somewhere below it.
    ///
    /// It does NOT delay the work. The pacer runs on its own clock beside the
    /// task group, which starts at the same moment it does.
    private struct Stop {
        var mark: Double
        var dwell: Duration
    }

    private static let stops: [Stop] = [
        Stop(mark: 0.11, dwell: .seconds(1)),
        Stop(mark: 0.67, dwell: .seconds(2)),
    ]

    /// The band the bar is allowed to report inside, right now. The lower bound
    /// is the stop it has left, the upper the one it is sitting at.
    private var floorMark: Double = Preloader.stops[0].mark
    private var ceilingMark: Double = Preloader.stops[0].mark

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

        // Beside the work, never in front of it: this task and the group below
        // start together, and the only thing the pacer governs is how far
        // `publish` is willing to go. See `stops`.
        let pacer = Task { [self] in
            //R Seeded with the FIRST stop rather than 0, because the bar's
            //R opening move is to that stop — floor and ceiling are equal for
            //R the first dwell, which is what pins it at 11% while the work
            //R behind it may already have finished.
            var left = Self.stops[0].mark

            for stop in Self.stops {
                floorMark = left
                ceilingMark = stop.mark
                publish()
                try? await Task.sleep(for: stop.dwell)
                left = stop.mark
            }

            floorMark = left
            ceilingMark = 1
            publish()
        }

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
                publish()
            }
        }

        // The dwells add up to three seconds, so on a warm launch this is what
        // the splash's length actually is — the two-second floor below has
        // already elapsed inside it. Awaiting it is also what stops a stray
        // `publish` from landing after the bar has been set to 1.
        _ = await pacer.value

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

        // Full, and then a beat. See `fullDwell`.
        try? await Task.sleep(for: fullDwell)

        isFinished = true
    }

    /// Show what has actually landed, held inside the current stop's band.
    ///
    /// Both bounds earn their place. Without the floor the bar would fall back —
    /// the lightest step is weighted 0.30, so a launch where nothing has landed
    /// yet would drop it from 67% to nothing the moment a dwell ended. Without
    /// the ceiling there is no dwell at all: on a warm launch every step has
    /// landed before the first one is over.
    ///
    /// It never moves backwards regardless. A progress bar that retreats is a
    /// bug report, whatever the numbers underneath it are doing.
    private func publish() {
        let landed = Step.allCases
            .filter { done.contains($0) }
            .reduce(0) { $0 + $1.weight }
        let shown = min(ceilingMark, max(floorMark, landed))
        guard shown > progress else { return }
        withAnimation(.easeOut(duration: 0.35)) { progress = shown }
    }
}

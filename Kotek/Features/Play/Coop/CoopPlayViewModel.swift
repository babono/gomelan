//
//  CoopPlayViewModel.swift
//  Kotek
//
//  Two players, one screen: one `PlayEngine` per player on one display link
//  and one start time, so the halves cannot drift apart (§6.6.3). The first
//  engine sounds the gong; the second is silent under it.
//
//  ponytail: play-along only. Nothing is judged and nothing is filed — the
//  sensors are not wired in yet. When they are, each engine takes its own
//  gangsa's strikes and `judging` goes on; the clock already is the shared one
//  judging would need.
//

import FactoryKit
import Foundation
import Observation
import QuartzCore
import SwiftUI

@Observable
@MainActor
final class CoopPlayViewModel {
    struct Lane: Identifiable {
        let id: Int
        let player: CoopPlayer
        let profile: InstrumentProfile
        let engine = PlayEngine()

        var keyCount: Int {
            max(1, profile.keys.count)
        }
    }

    let app: AppState
    let cue: CuePlayer
    let kotekan: Kotekan?
    /// In seat order, left to right.
    let lanes: [Lane]
    private let displayLink = DisplayLink()

    var paused = false
    /// 3, 2, 1 between Resume and the clock running again, as in solo — two
    /// players need their hands back over the bilah too. Nil otherwise.
    private(set) var resumeCount: Int?
    private var resumeTask: Task<Void, Never>?
    private var pauseStartedAt: Double = 0

    /// Learn's Watch runs this too: both halves on this gangsa, unnamed,
    /// polos on the left, each sounding its own half.
    private let watching: Bool
    private var live = false

    init(app: AppState, cue: CuePlayer = Container.shared.cueService(), watching: Bool = false) {
        self.app = app
        self.cue = cue
        self.watching = watching
        kotekan = app.selectedKotekan
        let players = watching
            ? [KotekanHalf.polos, .sangsih].map { CoopPlayer(name: "", instrumentID: app.profile.id, half: $0) }
            : (app.coop ?? CoopSetup(playerName: app.playerName, instrumentID: app.profile.id)).players
        lanes = players.enumerated().map { i, player in
            Lane(id: i, player: player, profile: app.coopProfile(player))
        }
    }

    var voicedKeys: ClosedRange<Int> {
        kotekan?.voicedKeyRange ?? 0 ... 0
    }

    /// The first lane's engine — the one with the gong — speaks for both.
    var clock: PlayEngine {
        lanes[0].engine
    }

    // MARK: - Lifecycle

    func setup() {
        guard let kotekan else { return }
        live = true
        // Watching, nobody plays along, so the halves are heard.
        let guideVoices = watching || (app.coop?.guideVoices ?? false)
        for lane in lanes {
            let engine = lane.engine
            engine.cue = cue
            engine.colotomicAudible = lane.id == 0
            engine.partnerAudible = false
            engine.yourVoiceAudible = guideVoices
            // Polos from the left of the stereo field, sangsih from the right,
            // whoever sits where — the halves read as two players by ear too.
            engine.yourPan = lane.player.half == .polos ? -0.32 : 0.32
            // No partner half in either lane: the partner is the other lane,
            // drawn in full beside it, not a ghost inside this one.
            engine.configure(
                song: kotekan.makeSong(half: lane.player.half, cycles: 1),
                profile: lane.profile,
                // Watching is the figure as written; coop plays at the pair's speed.
                tempoScale: watching ? 1 : app.tempoScale,
                judging: false
            )
        }

        // One stamp for both — see `PlayEngine.start(at:)`. The cue player
        // goes up first, as `start()` does, so its boot is not on the clock.
        cue.start()
        let now = CACurrentMediaTime()
        for lane in lanes {
            lane.engine.start(at: now)
        }
        displayLink.onFrame = { [weak self] now in
            guard let self else { return }
            for lane in lanes {
                lane.engine.tick(now: now)
            }
        }
        displayLink.start()
    }

    func teardown() {
        // Once: Watch tears down before moving on, then again on disappear,
        // and a late `cue.stop()` would silence the next step's session.
        guard live else { return }
        live = false
        resumeTask?.cancel()
        displayLink.stop()
        cue.stop()
    }

    // MARK: - Controls

    /// A tap, unless the opening count-in is running — see
    /// `WaterfallPlayViewModel.tapped`.
    func tapped() {
        if clock.msUntilFirstNote == nil { pause() }
    }

    func pause() {
        guard !paused else { return }
        paused = true
        pauseStartedAt = CACurrentMediaTime()
        displayLink.stop()
        cue.stopKeySamples()
    }

    /// Count 3, 2, 1, then run. Still paused while it counts, so the clock is
    /// shifted past the countdown too — see `WaterfallPlayViewModel.resume`.
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
        let seconds = CACurrentMediaTime() - pauseStartedAt
        for lane in lanes {
            lane.engine.resumeAfterPause(seconds: seconds)
        }
        displayLink.start()
        paused = false
    }

    /// Backgrounded mid-count: stay paused, and ask for Resume again.
    private func cancelResume() {
        resumeTask?.cancel()
        resumeTask = nil
        resumeCount = nil
    }

    /// Both lanes at once, on one instant — see `PlayEngine.setTempoScale`.
    /// Tempo is set while paused now, so anchored at the pause, as in solo:
    /// anchored to now, the resume added the whole pause on top.
    func tempoChanged(_ scale: Double) {
        let now = paused ? pauseStartedAt : CACurrentMediaTime()
        for lane in lanes {
            lane.engine.setTempoScale(scale, now: now)
        }
    }

    var guideVoices: Bool {
        app.coop?.guideVoices ?? false
    }

    func setGuideVoices(_ on: Bool) {
        app.coop?.guideVoices = on
        for lane in lanes {
            lane.engine.yourVoiceAudible = on
        }
        if !on { cue.stopKeySamples() }
    }

    func leave() {
        cancelResume()
        teardown()
        app.leaveCoop()
    }

    func handleScenePhase(_ phase: ScenePhase) {
        guard phase != .active else { return }
        cancelResume()
        pause()
    }
}

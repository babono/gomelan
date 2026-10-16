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
    private var pauseStartedAt: Double = 0

    init(app: AppState, cue: CuePlayer = Container.shared.cueService()) {
        self.app = app
        self.cue = cue
        kotekan = app.selectedKotekan
        let setup = app.coop ?? CoopSetup(playerName: app.playerName, instrumentID: app.profile.id)
        lanes = setup.players.enumerated().map { i, player in
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
        let guideVoices = app.coop?.guideVoices ?? false
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
                tempoScale: app.tempoScale,
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
        displayLink.stop()
        cue.stop()
    }

    // MARK: - Controls

    func pause() {
        guard !paused else { return }
        paused = true
        pauseStartedAt = CACurrentMediaTime()
        displayLink.stop()
        cue.stopKeySamples()
    }

    func resume() {
        guard paused else { return }
        let seconds = CACurrentMediaTime() - pauseStartedAt
        for lane in lanes {
            lane.engine.resumeAfterPause(seconds: seconds)
        }
        displayLink.start()
        paused = false
    }

    /// Both lanes at once, on one instant — see `PlayEngine.setTempoScale`.
    func tempoChanged(_ scale: Double) {
        let now = CACurrentMediaTime()
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
        teardown()
        app.leaveCoop()
    }

    func handleScenePhase(_ phase: ScenePhase) {
        if phase != .active { pause() }
    }
}

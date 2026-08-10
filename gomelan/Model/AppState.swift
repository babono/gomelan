//
//  AppState.swift
//  gomelan
//
//  The app-level state machine (PRD §13.4). Any state can return to .aligning
//  via a persistent "keys misaligned?" affordance — used often at the exhibition.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AppState {
    enum Screen: Equatable {
        case welcome
        case checkingPermissions
        case permissionsBlocked
        case framing
        case aligning
        case songList
        case songDetail
        case countdown
        case playing
        case results
        case settings
        case calibrating
        case malletTest
    }

    var screen: Screen = .welcome
    var profile: InstrumentProfile
    var songs: [Song]

    // Selection carried through the play flow.
    var selectedSong: Song?
    var playMode: PlayMode = .practice
    var lastResult: SongResult?

    // Practice-mode tempo (§5.3): 0.5, 0.75, 1.0
    var tempoScale: Double = 1.0
    // Audio cue toggles (§5.4)
    var metronomeEnabled: Bool = true
    var referenceToneEnabled: Bool = true

    init() {
        // A profile calibrated on the real instrument takes precedence over the
        // bundled placeholder.
        self.profile = ProfileStore.load() ?? ResourceLoader.defaultProfile()
        self.songs = ResourceLoader.bundledSongs()
    }

    func saveProfile() {
        ProfileStore.save(profile)
    }

    /// Songs the calibrated instrument can actually play (§4 Flow B).
    var availableSongs: [Song] {
        songs.filter { $0.requiredKeys <= profile.keyCount }
    }

    func song(_ song: Song, canPlayOn profile: InstrumentProfile) -> Bool {
        song.requiredKeys <= profile.keyCount
    }

    // MARK: - Transitions

    func begin() {
        screen = .checkingPermissions
    }

    func permissionsResolved(granted: Bool) {
        screen = granted ? .framing : .permissionsBlocked
    }

    func framingConfirmed() { screen = .aligning }
    func alignmentConfirmed() { screen = .songList }

    func select(_ song: Song) {
        selectedSong = song
        screen = .songDetail
    }

    func start(mode: PlayMode) {
        playMode = mode
        screen = .countdown
    }

    func countdownFinished() { screen = .playing }

    func finish(result: SongResult) {
        lastResult = result
        screen = .results
    }

    func retry() { screen = .countdown }
    func backToSongs() { screen = .songList }
    func openSettings() { screen = .settings }
    func closeSettings() { screen = .songList }
    func openCalibration() { screen = .calibrating }
    func calibrationFinished() { screen = .songList }
    func openMalletTest() { screen = .malletTest }
    func closeMalletTest() { screen = .settings }

    /// The persistent re-alignment affordance (§13.4).
    func realign() { screen = .aligning }
}

//
//  AppState.swift
//  gomelan
//
//  The app-level state machine (PRD §13.4). Setup runs in three numbered steps —
//  count the keys, frame the instrument, fit the mask — then learns the
//  instrument's voice (baseline), and lands on the kotekan picker. Any state can
//  return to .aligning via the persistent "realign" affordance.
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
        case chooseInstrument    // Multi-instrument selection
        case choosingKeyCount   // setup 1/3
        case framing            // setup 2/3
        case aligning           // setup 3/3
        case calibrating        // baseline · learn the voice
        case chooseKotekan
        case chooseHalf
        case countdown
        case playing
        case results
        case settings
        case malletTest
        case detectionTest
        case audioTest
    }

    var screen: Screen = .welcome
    var profile: InstrumentProfile
    var savedProfiles: [InstrumentProfile] = []

    // The kotekan session carried through selection → play.
    let kotekans: [Kotekan] = Kotekan.bundled
    var selectedKotekan: Kotekan?
    var chosenHalf: KotekanHalf = .polos
    var chosenCycles: Int = 8

    /// The rendered note sequence the PlayEngine runs, built from the session.
    var selectedSong: Song?
    var playMode: PlayMode = .play
    var lastResult: SongResult?

    // Practice-mode tempo (§5.3): 0.5, 0.75, 1.0
    var tempoScale: Double = 1.0
    // Audio cue toggles (§5.4)
    var metronomeEnabled: Bool = true
    var referenceToneEnabled: Bool = true

    /// Require a real gangsa strike sound (spectral baseline) to register a hit.
    var requireStrikeSound: Bool = false

    /// Whether the gangsa's strike-sound baseline has been learned this session.
    var baselineLearned: Bool = false

    init() {
        let all = ProfileStore.loadAll()
        self.savedProfiles = all
        if let current = ProfileStore.loadSelected() {
            self.profile = current
            self.baselineLearned = current.hasLearnedBaseline
            self.requireStrikeSound = current.hasLearnedBaseline
        } else {
            self.profile = ResourceLoader.defaultProfile()
        }
        self.screen = .welcome
    }

    func saveProfile() {
        ProfileStore.save(profile)
        savedProfiles = ProfileStore.loadAll()
    }

    /// Kotekan this instrument has enough keys for.
    func kotekan(_ k: Kotekan, playableOn profile: InstrumentProfile) -> Bool {
        k.requiredKeys <= profile.keyCount
    }

    // MARK: - Instrument Selection & Management

    func selectInstrument(_ p: InstrumentProfile) {
        profile = p
        ProfileStore.setSelectedID(p.id)
        baselineLearned = p.hasLearnedBaseline
        requireStrikeSound = p.hasLearnedBaseline
        screen = .chooseKotekan
    }

    private var isAddingNewInstrument = false
    private var previousProfile: InstrumentProfile? = nil

    func addNewInstrument() {
        let count = savedProfiles.count + 1
        let newID = UUID().uuidString
        let name = "Gangsa #\(count)"
        let dateStr = ISO8601DateFormatter().string(from: Date())
        let newProfile = InstrumentProfile(id: newID, name: name, keyCount: 10, createdAt: dateStr, keys: InstrumentProfile.layout(count: 10))

        isAddingNewInstrument = true
        previousProfile = profile
        profile = newProfile
        screen = .choosingKeyCount
    }

    func cancelInstrumentSetup() {
        if isAddingNewInstrument {
            if let prev = previousProfile {
                profile = prev
                ProfileStore.setSelectedID(prev.id)
            }
            isAddingNewInstrument = false
            previousProfile = nil
        }
        savedProfiles = ProfileStore.loadAll()
        if savedProfiles.isEmpty {
            screen = .welcome
        } else {
            screen = .chooseInstrument
        }
    }

    func realignInstrument(_ p: InstrumentProfile) {
        profile = p
        ProfileStore.setSelectedID(p.id)
        screen = .aligning
    }

    func deleteInstrument(_ profileID: String) {
        ProfileStore.delete(profileID)
        savedProfiles = ProfileStore.loadAll()
        if profile.id == profileID {
            if let next = savedProfiles.first {
                profile = next
                ProfileStore.setSelectedID(next.id)
            }
        }
    }

    func openChooseInstrument() {
        savedProfiles = ProfileStore.loadAll()
        screen = .chooseInstrument
    }

    // MARK: - Onboarding

    func begin() {
        savedProfiles = ProfileStore.loadAll()
        if savedProfiles.isEmpty {
            addNewInstrument()
        } else {
            screen = .chooseInstrument
        }
    }

    func permissionsResolved(granted: Bool) {
        if granted {
            if !savedProfiles.isEmpty {
                screen = .chooseInstrument
            } else {
                addNewInstrument()
            }
        } else {
            screen = .permissionsBlocked
        }
    }

    /// Step 1/3: how many keys does this instrument have? Chosen before framing
    /// so the framing and mask steps know how many bilah to draw.
    func keyCountChosen(_ count: Int) {
        var updated = profile
        updated.resize(to: count)
        profile = updated
        if !isAddingNewInstrument {
            saveProfile()
        }
        screen = .framing
    }

    /// Step 2/3 → 3/3.
    func framingConfirmed() { screen = .aligning }

    /// Step 3/3 leads into the baseline: the app learns what a real gangsa strike
    /// sounds like on THIS instrument before it can tell strikes from noise. Once
    /// learned this session, re-aligning skips straight back to the picker.
    func alignmentConfirmed() {
        saveProfile()
        if isAddingNewInstrument {
            isAddingNewInstrument = false
            previousProfile = nil
        }
        screen = baselineLearned ? .chooseKotekan : .calibrating
    }

    /// Baseline captured: strikes will now be confirmed by sound, and the picker
    /// is next.
    func baselineFinished() {
        baselineLearned = true
        requireStrikeSound = true
        saveProfile()
        screen = .chooseKotekan
    }

    /// Left the baseline step without capturing — go on anyway (vision alone).
    func skipCalibration() {
        saveProfile()
        screen = .chooseKotekan
    }

    // MARK: - Session selection

    /// Picked a kotekan and how many times around; go choose which half to play.
    func chooseKotekan(_ k: Kotekan, cycles: Int) {
        selectedKotekan = k
        chosenCycles = cycles
        screen = .chooseHalf
    }

    /// Picked a half; render the session and start the countdown.
    func startSession(half: KotekanHalf) {
        guard let k = selectedKotekan else { return }
        chosenHalf = half
        selectedSong = k.makeSong(half: half, cycles: chosenCycles)
        playMode = .play
        screen = .countdown
    }

    func countdownFinished() { screen = .playing }

    func finish(result: SongResult) {
        lastResult = result
        screen = .results
    }

    // MARK: - Navigation

    func retry() { screen = .countdown }
    func backToKotekan() { screen = .chooseKotekan }
    func backToHalf() { screen = .chooseHalf }
    func openSettings() { screen = .settings }
    func closeSettings() { screen = .chooseKotekan }
    func openCalibration() { screen = .calibrating }
    func openMalletTest() { screen = .malletTest }
    func closeMalletTest() { screen = .settings }
    func openDetectionTest() { screen = .detectionTest }
    func closeDetectionTest() { screen = .settings }
    func openAudioTest() { screen = .audioTest }
    func closeAudioTest() { screen = .settings }

    /// The persistent re-alignment affordance (§13.4).
    func realign() { screen = .aligning }
}

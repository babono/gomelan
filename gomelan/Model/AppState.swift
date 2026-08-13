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
        case baseline
        case chooseKotekan
        case chooseHalf
        case chooseCycles       // Dedicated repetition/cycles screen
        case watching           // demo · the app plays it, you watch and listen
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
    /// The other half of the kotekan — what a partner would be playing beside
    /// you. The app plays it so the interlock is there even when you practise
    /// alone (§7); the gong layer is always underneath both.
    var partnerSong: Song?
    /// Whether the app plays your partner's half during your turn.
    var partnerAudible: Bool = true
    var playMode: PlayMode = .play
    var lastResult: SongResult?

    // Practice-mode tempo (§5.3): 0.5, 0.75, 1.0
    var tempoScale: Double = 1.0
    /// Speed the demo screen plays the figure back at — the run itself is
    /// always at tempo, so slowing the demo down is free.
    var demoTempoScale: Double = 1.0
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

    /// The same save, off the main actor. Used by the steps that show a "saving"
    /// state: it keeps the spinner honest — it is up while real work happens,
    /// rather than for one frame around a synchronous write — and keeps the disk
    /// off the thread drawing it.
    func saveProfileAsync() async {
        let snapshot = profile
        savedProfiles = await Task.detached {
            ProfileStore.save(snapshot)
            return ProfileStore.loadAll()
        }.value
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

    /// The area the player framed the instrument into (step 2/3), normalised to
    /// the full-bleed camera space. It is the search region for key prediction
    /// and the fallback layout's bounds — everything outside it is table, floor
    /// and the wooden frame ends.
    /// Pushed out to the corners on purpose: the chrome floats over the feed, so
    /// the only space this has to leave is the strip the caption sits in. The
    /// bigger it is, the more of the frame the instrument can fill, and the more
    /// pixels per bilah the prediction and the strike classifier both get.
    var framedRegion = NormalizedRect(x: 0.03, y: 0.09, w: 0.94, h: 0.775)

    /// Set when arriving at 3/3 from framing (rather than a later re-align), so
    /// the masks start from the area just framed instead of a saved fit.
    var seedMasksFromFraming = false

    /// Step 2/3 → 3/3.
    func framingConfirmed() {
        seedMasksFromFraming = true
        screen = .aligning
    }

    /// Step 3/3 leads into the baseline: the app learns what a real gangsa strike
    /// sounds like on THIS instrument before it can tell strikes from noise.
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

    /// As above, but awaits the write so the caller can hold a "saving" state
    /// over it instead of flashing one.
    func baselineFinishedAsync() async {
        baselineLearned = true
        requireStrikeSound = true
        await saveProfileAsync()
        screen = .chooseKotekan
    }

    /// Left the baseline step without capturing — go on anyway (vision alone).
    func skipCalibration() {
        saveProfile()
        screen = .chooseKotekan
    }

    // MARK: - Session selection

    /// Step 1: Picked a kotekan figure; advance to choose half.
    func chooseKotekan(_ k: Kotekan) {
        selectedKotekan = k
        screen = .chooseHalf
    }

    /// Step 2: Picked a half (Polos/Sangsih); advance to choose cycles.
    func chooseHalf(_ half: KotekanHalf) {
        chosenHalf = half
        screen = .chooseCycles
    }

    /// Step 3: Picked cycles; render the session and go and watch it first.
    ///
    /// The demo and the run are two screens now (§4 Flow C): you watch and hear
    /// the figure for as long as you like, then take the instrument yourself.
    func startSession(cycles: Int) {
        guard let k = selectedKotekan else { return }
        chosenCycles = cycles
        selectedSong = k.makeSong(half: chosenHalf, cycles: cycles)
        partnerSong = k.makeSong(half: chosenHalf.other, cycles: cycles)
        playMode = .play
        demoTempoScale = 1.0
        screen = .watching
    }

    /// One cycle of the chosen figure — what the demo screen loops.
    var demoSong: Song? {
        selectedKotekan?.makeSong(half: chosenHalf, cycles: 1)
    }

    /// The same cycle for the other half, so the demo can sound the whole weave.
    var demoPartnerSong: Song? {
        selectedKotekan?.makeSong(half: chosenHalf.other, cycles: 1)
    }

    /// Watched enough — hand the instrument over.
    func beginPractice() { screen = .countdown }

    /// Back from the demo to the cycle picker.
    func backToCycles() { screen = .chooseCycles }

    /// Watch the figure again (from the demo screen or the results screen).
    func watchAgain() { screen = .watching }

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
    func calibrationFinished() { screen = .chooseKotekan }
    func openBaseline() { screen = .baseline }
    func openMalletTest() { screen = .malletTest }
    func closeMalletTest() { screen = .settings }
    func openDetectionTest() { screen = .detectionTest }
    func closeDetectionTest() { screen = .settings }
    func openAudioTest() { screen = .audioTest }
    func closeAudioTest() { screen = .settings }

    /// The persistent re-alignment affordance (§13.4).
    func realign() { screen = .aligning }
}

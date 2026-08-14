//
//  AppState.swift
//  gomelan
//
//  The app-level state machine (PRD §13.4). Setup runs in four numbered steps —
//  count the keys, frame the instrument, fit the mask, learn the instrument's
//  voice (baseline) — and lands on the kotekan picker. Any state can
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
        case choosingKeyCount   // setup 1/4
        case framing            // setup 2/4
        case aligning           // setup 3/4
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
    /// The three voices, mutable independently and shared between the demo and
    /// the run, so a choice made while listening carries into playing.
    var partnerAudible: Bool = true
    var yourVoiceAudible: Bool = true
    var colotomicAudible: Bool = true

    /// Whether the scrolling score is shown. Off gives the bilah the whole
    /// screen, which is where the guidance you play from actually is.
    var riverVisible: Bool = true
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

    /// Save a specific instrument, which may not be the active one — renaming a
    /// card in the list, for instance.
    func saveInstrument(_ p: InstrumentProfile) {
        ProfileStore.save(p)
        //R `ProfileStore.save` also marks what it saved as selected, which is
        //R right when it IS the active instrument and wrong otherwise.
        ProfileStore.setSelectedID(profile.id)
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
        savedProfiles = ProfileStore.loadAll()
        if isAddingNewInstrument {
            //R Only restore an instrument that still exists: it can have been
            //R deleted from the list before setup was cancelled.
            if let prev = previousProfile, savedProfiles.contains(where: { $0.id == prev.id }) {
                profile = prev
                ProfileStore.setSelectedID(prev.id)
            }
            isAddingNewInstrument = false
            previousProfile = nil
        }
        // Back to the list either way — it handles being empty now.
        screen = .chooseInstrument
    }

    func realignInstrument(_ p: InstrumentProfile) {
        profile = p
        ProfileStore.setSelectedID(p.id)
        screen = .aligning
    }

    /// Delete an instrument, including the last one — an instrument you can't
    /// get rid of is a bug, not a safeguard.
    ///
    /// The delicate part is forgetting it EVERYWHERE. `profile` is what the next
    /// `saveProfile()` writes, and `ProfileStore.save` re-inserts anything it
    /// doesn't already find — so leaving the deleted instrument sitting in
    /// `profile` (or parked in `previousProfile` by an in-progress setup) means
    /// it quietly comes back the next time anything is saved.
    func deleteInstrument(_ profileID: String) {
        ProfileStore.delete(profileID)
        savedProfiles = ProfileStore.loadAll()

        if previousProfile?.id == profileID { previousProfile = nil }
        guard profile.id == profileID else { return }

        if let next = savedProfiles.first {
            profile = next
            ProfileStore.setSelectedID(next.id)
            baselineLearned = next.hasLearnedBaseline
            requireStrikeSound = next.hasLearnedBaseline
        } else {
            // Nothing left: back to the same state as a fresh install, so the
            // empty list offers setup rather than pointing at a ghost.
            profile = ResourceLoader.defaultProfile()
            ProfileStore.setSelectedID("")
            baselineLearned = false
            requireStrikeSound = false
        }
    }

    func openChooseInstrument() {
        savedProfiles = ProfileStore.loadAll()
        screen = .chooseInstrument
    }

    // MARK: - Onboarding

    /// Always the instrument list, even when it is empty — it is the home for
    /// instruments, and dropping a first-time player straight into a three-step
    /// setup gives them no idea where they are or how to get back out.
    func begin() {
        savedProfiles = ProfileStore.loadAll()
        screen = .chooseInstrument
    }

    func permissionsResolved(granted: Bool) {
        screen = granted ? .chooseInstrument : .permissionsBlocked
    }

    /// Step 1/4: how many keys does this instrument have? Chosen before framing
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

    /// The area the player framed the instrument into (step 2/4), normalised to
    /// the full-bleed camera space. It is the search region for key prediction
    /// and the fallback layout's bounds — everything outside it is table, floor
    /// and the wooden frame ends.
    /// Pushed out to the corners on purpose: the chrome floats over the feed, so
    /// the only space this has to leave is the strip the caption sits in. The
    /// bigger it is, the more of the frame the instrument can fill, and the more
    /// pixels per bilah the prediction and the strike classifier both get.
    /// The bottom stops short of the caption strip by design — the dashed edge
    /// and the Continue button sharing a line read as a collision.
    var framedRegion = NormalizedRect(x: 0.03, y: 0.09, w: 0.94, h: 0.745)

    /// Set when arriving at 3/4 from framing (rather than a later re-align), so
    /// the masks start from the area just framed instead of a saved fit.
    var seedMasksFromFraming = false

    /// Step 2/4 → 3/4.
    func framingConfirmed() {
        seedMasksFromFraming = true
        screen = .aligning
    }

    /// Step 3/4 leads into the baseline (4/4): the app learns what a real gangsa strike
    /// sounds like on THIS instrument before it can tell strikes from noise.
    /// The caller has already written the profile (it holds a "saving" state
    /// over the write and the lens lock), so this only advances.
    func alignmentConfirmed() {
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

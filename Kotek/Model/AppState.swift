//
//  AppState.swift
//  Kotek
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
        case countdown
        case playing
        case results
        case settings
        case malletTest
        case detectionTest
        case audioTest
        case captureTraining
    }

    var screen: Screen = .welcome
    var profile: InstrumentProfile
    var savedProfiles: [InstrumentProfile] = []

    // The kotekan session carried through selection → play.
    let kotekans: [Kotekan] = Kotekan.bundled
    var selectedKotekan: Kotekan?
    /// Which half you are taking. Live: it is a toggle on the practice screen
    /// now, not a screen of its own, so it can change mid-session.
    var chosenHalf: KotekanHalf = .polos

    /// The rendered note sequence the PlayEngine runs, built from the session.
    var selectedSong: Song?
    /// The other half of the kotekan — what a partner would be playing beside
    /// you. The app plays it so the interlock is there even when you practise
    /// alone (§7); the gong layer is always underneath both.
    var partnerSong: Song?
    /// The two voices you can silence. Your own half starts muted — you are the
    /// one playing it — and turning it on has the app play along, which is what
    /// the "watch and listen" screen used to be for. The gong is not on this
    /// list: it is the frame everything is judged against.
    var partnerAudible: Bool = true
    var yourVoiceAudible: Bool = false

    /// Whether the scrolling score is shown. Off gives the bilah the whole
    /// screen, which is where the guidance you play from actually is.
    var riverVisible: Bool = true
    var lastResult: SongResult?

    // Practice-mode tempo (§5.3): 0.5, 0.75, 1.0
    var tempoScale: Double = 1.0
    // Audio cue toggles (§5.4)
    var metronomeEnabled: Bool = true
    var referenceToneEnabled: Bool = true

    /// Require a real gangsa strike sound (spectral baseline) to register a hit.
    var requireStrikeSound: Bool = false

    // MARK: - Detection tuning
    //
    // Owned here rather than by the test screen, because they ARE the detector's
    // behaviour, not a debug view's local state. Tuning them somewhere the
    // numbers are visible and then playing with different values would make the
    // test screen actively misleading.
    //
    // Persisted, unlike the practice settings above: these are calibrated once
    // against a particular model and instrument, and losing them on relaunch —
    // the morning of an exhibition, say — would be silent and expensive.

    /// Confidence vision must reach to name a bar. See DetectionTestView.
    var visionThreshold: Double = Defaults.double("visionThreshold", 0.5) {
        didSet { Defaults.set("visionThreshold", visionThreshold) }
    }

    /// Whether an audio onset must corroborate a sighting before it counts.
    /// Silence vetoes vision: a gangsa strike is the loudest thing in the room.
    var requireOnsetCorroboration: Bool = Defaults.bool("requireOnset", true) {
        didSet { Defaults.set("requireOnset", requireOnsetCorroboration) }
    }

    /// Whether the ear fires the trigger and vision only says WHICH bar.
    ///
    /// Correct for a presence model, which reports that the mallet is over a bar
    /// and stays true while it lingers — so a rising edge in the vision score
    /// fires once and then latches, losing every repeated note. An onset is
    /// impulsive and has no such problem.
    var audioTriggersStrikes: Bool = Defaults.bool("audioTriggers", true) {
        didSet { Defaults.set("audioTriggers", audioTriggersStrikes) }
    }

    /// Index into the fill/centre/fit options. Must match how the current model
    /// was trained — see MalletHitClassifier.cropAndScale.
    var cropScaleMode: Int = Defaults.int("cropScaleMode", 1) {
        didSet { Defaults.set("cropScaleMode", cropScaleMode) }
    }

    /// The phone is on a stand or arm rather than in someone's hand.
    ///
    /// Continuous autofocus is right for a handheld phone and actively harmful
    /// on a fixed rig: hands passing over the bilah make it hunt, and every
    /// refocus shifts sharpness and framing slightly — variation the strike
    /// classifier reads as signal, on top of a scene that is otherwise perfectly
    /// still. Locking both focus and exposure is what turns a mount into a
    /// genuinely constant image.
    var fixedMount: Bool = false

    /// Whether the gangsa's strike-sound baseline has been learned this session.
    var baselineLearned: Bool = false

    init() {
        let all = ProfileStore.loadAll()
        MalletHitClassifier.applyCropScale(mode: Defaults.int("cropScaleMode", 1))
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

    /// Fold the audio dictionary a session learned back into the instrument.
    ///
    /// Written straight to disk without touching `screen` or anything else the
    /// UI observes — this lands as the results screen is appearing, and a
    /// session's worth of listening is not worth a redraw.
    func storeLinearTemplates(_ templates: [Int: [Float]]) {
        guard !templates.isEmpty else { return }
        var changed = false
        for (index, vector) in templates {
            guard let position = profile.keys.firstIndex(where: { $0.index == index }) else { continue }
            if profile.keys[position].linearTemplate != vector {
                profile.keys[position].linearTemplate = vector
                changed = true
            }
        }
        guard changed else { return }
        saveProfile()
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

    /// Make this the active instrument without leaving the picker.
    ///
    /// Still here even though tapping a card now goes straight through: the
    /// picker uses it to land on a real instrument when the active one is not
    /// on the rail, and it is the half of `selectInstrument` that has nothing
    /// to do with navigation.
    func activateInstrument(_ p: InstrumentProfile) {
        profile = p
        ProfileStore.setSelectedID(p.id)
        baselineLearned = p.hasLearnedBaseline
        requireStrikeSound = p.hasLearnedBaseline
    }

    /// Pick this instrument and go. One tap, because "which instrument" is the
    /// only question the picker asks and a Next button underneath a card you
    /// already tapped is a second confirmation of a decision nobody was in
    /// doubt about. Renaming, re-aligning, recalibrating and deleting all live
    /// in Settings, per instrument — the card carries none of them.
    func selectInstrument(_ p: InstrumentProfile) {
        activateInstrument(p)
        screen = .chooseKotekan
    }

    private var isAddingNewInstrument = false
    private var previousProfile: InstrumentProfile? = nil

    func addNewInstrument() {
        let count = savedProfiles.count + 1
        let newID = UUID().uuidString
        let name = "Gangsa #\(count)"
        //R One ISO8601 spelling for the whole app. `createdAt` is the rail's
        //R sort key until an instrument has been played, so a format the parser
        //R in `InstrumentProfile.date(from:)` cannot read would silently drop
        //R every new instrument to the far end of the rail.
        let newProfile = InstrumentProfile(id: newID, name: name, keyCount: 10,
                                           createdAt: InstrumentProfile.nowISO(),
                                           keys: InstrumentProfile.layout(count: 10))

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

    /// Step 1/4: how many keys does this gangsa have, and what is it called?
    /// The count is chosen before framing so the framing and mask steps know how
    /// many bilah to draw.
    ///
    /// The name rides along because this screen is only ever reached from
    /// `addNewInstrument` — it IS the new-gangsa step. Naming it here, next to
    /// the one other fact the app cannot infer, saves the player a trip to
    /// Settings to fix "Gangsa #4" once they already have four of them.
    func keyCountChosen(_ count: Int, name: String) {
        var updated = profile
        updated.resize(to: count)
        //R An empty field keeps the generated name rather than writing a blank:
        //R a nameless card is unpickable on the rail, and a cleared field is far
        //R more likely to be an unfinished edit than an intention. Same guard as
        //R Settings' rename.
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { updated.name = trimmed }
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
    /// Take this figure and go.
    ///
    /// The count-in is now the only thing between the picker and playing. There
    /// used to be three screens here — which half, how many cycles, and a demo
    /// to sit through — and a gangsa player's verdict was that it is too much
    /// asked before you can strike a bilah. Which half is a toggle on the
    /// practice screen; how many cycles has no answer, because it loops until
    /// you stop it; and the demo is the guide voice, one tap away mid-practice.
    func chooseKotekan(_ k: Kotekan) {
        selectedKotekan = k
        renderHalves()
        screen = .countdown
    }

    /// Change sides without leaving the session.
    func setHalf(_ half: KotekanHalf) {
        guard half != chosenHalf else { return }
        chosenHalf = half
        renderHalves()
    }

    /// ONE cycle of each half. The engine repeats it for as long as the player
    /// wants — rendering N copies up front is what the cycles screen existed to
    /// choose, and there is no N any more.
    private func renderHalves() {
        guard let k = selectedKotekan else { return }
        selectedSong = k.makeSong(half: chosenHalf, cycles: 1)
        partnerSong = k.makeSong(half: chosenHalf.other, cycles: 1)
    }

    /// Step 2: Picked a half (Polos/Sangsih); advance to choose cycles.
    func countdownFinished() { screen = .playing }

    func finish(result: SongResult) {
        //R `landedNotes`, not the judgement list: that one is scoped to the half
        //R the session ended on, and time spent on the other side of the kotekan
        //R is just as much time spent on this gangsa.
        recordSession(landed: result.landedNotes)
        lastResult = result
        screen = .results
    }

    /// Fold a finished session into the active instrument: when it was played,
    /// and how much of it landed.
    ///
    /// Written at the END of a run rather than the start, where a disk write
    /// would sit between the countdown and the first beat. By the time this
    /// fires the rail is two screens away, so re-sorting it costs nothing.
    private func recordSession(landed: Int) {
        var updated = profile
        updated.lastUsedAt = InstrumentProfile.nowISO()
        updated.sessionCount = updated.sessionsPlayed + 1
        updated.accurateNotes = updated.notesLanded + landed
        profile = updated
        saveProfile()
    }

    // MARK: - Navigation

    func retry() { screen = .countdown }
    func backToKotekan() { screen = .chooseKotekan }
    func openSettings() { screen = .settings }
    func closeSettings() { screen = .chooseKotekan }
    func openCalibration() { screen = .calibrating }
    func calibrationFinished() { screen = .chooseKotekan }
    func openBaseline() { screen = .baseline }
    func openMalletTest() { screen = .malletTest }
    func closeMalletTest() { screen = .settings }
    func openDetectionTest() { screen = .detectionTest }
    func openCaptureTraining() { screen = .captureTraining }
    func closeCaptureTraining() { screen = .settings }
    func closeDetectionTest() { screen = .settings }
    func openAudioTest() { screen = .audioTest }
    func closeAudioTest() { screen = .settings }

    /// The persistent re-alignment affordance (§13.4).
    func realign() { screen = .aligning }
}

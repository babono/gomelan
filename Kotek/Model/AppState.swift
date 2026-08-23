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
    /// The two voices you can silence, in the order a figure is learned.
    ///
    /// YOUR half sounds by default. You cannot copy what you have not heard —
    /// this is how kotekan is taught, the teacher plays the part and you take
    /// it — so the app states the expectation first and the bilah light in time
    /// with it. Mute it once the figure is in your hands and the only polos in
    /// the room is yours.
    ///
    /// The PARTNER starts silent, and is the reward rather than the setting:
    /// turn it on and you are suddenly playing against the other half, which is
    /// what a kotekan actually is. Arriving in both parts at once, before you
    /// know either, is just a lot of bronze.
    ///
    /// The gong is on neither list. It is the frame everything is judged
    /// against, so it is never optional.
    var partnerAudible: Bool = false
    var yourVoiceAudible: Bool = true

    /// Whether the practice screen's bottom panel — the half switch, the tempo,
    /// the voice chips and the score — is up.
    ///
    /// DOWN by default. The guidance you play from is the bilah lighting up on
    /// the gangsa in front of you; the score is peripheral context, and the
    /// panel sits over exactly the part of the frame the instrument is most
    /// likely to be in. It is one tap away in the top bar for when it is wanted.
    var bottomBarVisible: Bool = false
    var lastResult: SongResult?
    /// What the figure's record was BEFORE the session that just ended, and
    /// whether that session beat it. Read by the results screen; set by
    /// `finish`, which is the only place that can tell, because filing the new
    /// record destroys the old one.
    var previousRecord: Double?
    var lastSetRecord = false
    /// The gangsa's landed-note total BEFORE the session that just ended, so
    /// the results screen can animate from it to where it is now. Captured for
    /// the same reason as `previousRecord`: crediting the session destroys the
    /// number the animation has to start from.
    var previousNotesLanded: Int?

    // Practice-mode tempo (§5.3): 0.5, 0.75, 1.0
    var tempoScale: Double = 1.0
    // Audio cue toggles (§5.4)
    var metronomeEnabled: Bool = true
    var referenceToneEnabled: Bool = true

    /// A sighting the microphone did not hear is discarded. See `DetectionMode`.
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

    /// Whether the ear fires the trigger and vision only says WHICH bar.
    ///
    /// Correct for a presence model, which reports that the mallet is over a bar
    /// and stays true while it lingers — so a rising edge in the vision score
    /// fires once and then latches, losing every repeated note. An onset is
    /// impulsive and has no such problem.
    var audioTriggersStrikes: Bool = Defaults.bool("audioTriggers", true) {
        didSet { Defaults.set("audioTriggers", audioTriggersStrikes) }
    }

    /// The three ways the two sensors can be arranged, as one choice instead of
    /// two booleans whose interaction nobody could predict from their names.
    ///
    /// The camera always triggers. What varies is whether the microphone gets a
    /// vote, and whether it gets a veto — and those are not a sensitivity dial
    /// in the same direction, which is exactly why two switches were the wrong
    /// shape for it. A vote makes detection MORE willing, a veto makes it less,
    /// and the pair had four states, two of which nobody would ever want.
    enum DetectionMode: String, CaseIterable, Identifiable {
        case cameraOnly
        case cameraAndMic
        case heardOnly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .cameraOnly:   return "Camera"
            case .cameraAndMic: return "Camera + mic"
            case .heardOnly:    return "Heard only"
            }
        }

        /// Written as a symptom, not a mechanism. Nobody opens this menu
        /// curious about sensor fusion; they open it because something is
        /// wrong, and the fastest way to the right setting is a line that
        /// describes what is wrong.
        var detail: String {
            switch self {
            case .cameraOnly:
                return "The microphone is ignored, so nothing in the room can trigger a stroke or block one. Use this in a loud hall — a mallet that hovers over a bar can still register."
            case .cameraAndMic:
                return "Either can register a stroke. The most willing of the three, and the microphone is what catches a bar struck twice in a row, which the camera cannot see."
            case .heardOnly:
                return "A stroke counts only where the camera sees one and the microphone hears the attack. Use this when strokes register that you did not play."
            }
        }
    }

    var detectionMode: DetectionMode {
        get {
            if !audioTriggersStrikes { return .cameraOnly }
            return requireStrikeSound ? .heardOnly : .cameraAndMic
        }
        set {
            audioTriggersStrikes = newValue != .cameraOnly
            requireStrikeSound = newValue == .heardOnly
        }
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

    /// The explainers, one per screen that has something to explain.
    ///
    /// Split rather than one long panel because they answer questions asked at
    /// different moments: `app` is "what is this thing and what is the grade",
    /// asked at the instrument picker where a rank is already on a card, and
    /// `kotekan` is "what am I actually choosing between", asked one screen
    /// later. Reading the second before you have an instrument would be reading
    /// about something you cannot yet do.
    enum Guide: String, CaseIterable, Identifiable {
        case app
        case kotekan

        var id: String { rawValue }
        /// `app` keeps the original key so anyone who has already dismissed it
        /// is not shown it again by this change.
        var seenKey: String { self == .app ? "hasSeenGuide" : "hasSeenGuide.\(rawValue)" }
    }

    /// Which panel is up, if any. Presented by `RootView` so it can cover any
    /// screen, rather than by whichever one happens to own the question mark.
    var visibleGuide: Guide?
    /// Survives relaunch: each panel introduces itself once, on a first run, and
    /// after that is only ever asked for. A guide that reappears is an obstacle,
    /// not an introduction.
    private var seen: Set<String> = Set(Guide.allCases.filter { Defaults.bool($0.seenKey, false) }
                                                      .map(\.rawValue))

    /// The practice screen's control tour. Not a `Guide` — it is a spotlight on
    /// live controls rather than a panel of prose, and it is shown by the screen
    /// that owns those controls rather than by `RootView`.
    private(set) var hasSeenPracticeCoach = Defaults.bool("hasSeenPracticeCoach", false)

    func markPracticeCoachSeen() {
        guard !hasSeenPracticeCoach else { return }
        hasSeenPracticeCoach = true
        Defaults.set("hasSeenPracticeCoach", true)
    }

    func openGuide(_ guide: Guide) { visibleGuide = guide }

    func closeGuide() {
        if let visibleGuide { markSeen(visibleGuide) }
        visibleGuide = nil
    }

    /// Show it unprompted the first time, and only the first time.
    func showGuideIfFirstRun(_ guide: Guide) {
        guard !seen.contains(guide.rawValue), visibleGuide == nil else { return }
        visibleGuide = guide
    }

    private func markSeen(_ guide: Guide) {
        guard !seen.contains(guide.rawValue) else { return }
        seen.insert(guide.rawValue)
        Defaults.set(guide.seenKey, true)
    }

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
    func storeLinearTemplates(_ atoms: [Int: LearnedAtom]) {
        guard !atoms.isEmpty else { return }
        var changed = false
        for (index, atom) in atoms {
            guard let position = profile.keys.firstIndex(where: { $0.index == index }) else { continue }
            //R The count matters as much as the vector. Storing one without the
            //R other is what made a half-learned key unsaveable.
            if profile.keys[position].linearTemplate != atom.bands
                || profile.keys[position].linearTemplateCount != atom.examples {
                profile.keys[position].linearTemplate = atom.bands
                profile.keys[position].linearTemplateCount = atom.examples
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
        fileRecord(result)
        //R `landedNotes`, not the judgement list: that one is scoped to the half
        //R the session ended on, and time spent on the other side of the kotekan
        //R is just as much time spent on this gangsa.
        recordSession(landed: result.landedNotes)
        lastResult = result
        screen = .results
    }

    /// File the session's best window as this figure's record, if it is one.
    ///
    /// Gated on a FULL window. `SongResult.best` scores a short session over
    /// whatever it has, which is right for telling you how three cycles went and
    /// wrong for a record: three good cycles are far easier than eight, and
    /// without this the leaderboard fills up with two-cycle sessions nobody
    /// could ever beat.
    private func fileRecord(_ result: SongResult) {
        previousRecord = nil
        lastSetRecord = false
        guard let k = selectedKotekan,
              result.cycles.count >= SongResult.scoringWindow,
              let best = result.best
        else { return }

        let half = chosenHalf.rawValue
        previousRecord = profile.record(kotekanId: k.id, half: half, tempo: tempoScale)?.accuracy
        var updated = profile
        lastSetRecord = updated.noteRecord(kotekanId: k.id, half: half,
                                           tempo: tempoScale, accuracy: best.accuracy)
        guard lastSetRecord else { return }
        profile = updated
        //R Written by `recordSession` a moment later, which saves the profile —
        //R no second trip to disk for the same session.
    }

    /// Fold a finished session into the active instrument: when it was played,
    /// and how much of it landed.
    ///
    /// Written at the END of a run rather than the start, where a disk write
    /// would sit between the countdown and the first beat. By the time this
    /// fires the rail is two screens away, so re-sorting it costs nothing.
    private func recordSession(landed: Int) {
        previousNotesLanded = profile.notesLanded
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

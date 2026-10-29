//
//  AppState.swift
//  Kotek
//
//  The app-level state machine (PRD §13.4). Setup runs in four numbered steps —
//  count the keys, frame the instrument, fit the mask, learn the instrument's
//  voice (baseline) — and lands on the kotekan picker. Any state can
//  return to .aligning via the persistent "realign" affordance.
//

import AppIntents
import FactoryKit
import Observation
import OSLog
import SwiftUI

@MainActor
@Observable
final class AppState {
    var screen: Route = .welcome
    var profile: InstrumentProfile {
        didSet {
            playsRecordedSounds = Self.playsRecordedSounds(profile.id)
            applyKeySounds()
        }
    }

    /// Whether this gangsa sounds its own recorded keys (Settings → Gangsa →
    /// Note clips) or the bundled samples. On by default: recording them is
    /// the point. A key with no recording plays the bundled sample either way.
    ///
    /// Per gangsa, kept on this device beside the recordings themselves.
    /// ponytail: not synced — the gangsa row has no column for it, and a second
    /// device would need the recordings first anyway.
    var playsRecordedSounds = true {
        didSet {
            Defaults.set(Self.recordedSoundsKey(profile.id), playsRecordedSounds)
            applyKeySounds()
        }
    }

    static func recordedSoundsKey(_ id: String) -> String {
        "playsRecordedSounds.\(id.lowercased())"
    }

    private static func playsRecordedSounds(_ id: String) -> Bool {
        Defaults.bool(recordedSoundsKey(id), true)
    }

    /// The cue player loads its key sounds when a session starts: this gangsa's
    /// recordings, or none — nil keeps the bundled samples.
    func applyKeySounds() {
        cue.instrumentID = playsRecordedSounds ? profile.id : nil
    }

    var savedProfiles: [InstrumentProfile] = []

    // The kotekan session carried through selection → play.
    /// The last catalogue Supabase sent (`KotekanStore`) until it answers
    /// again, then whatever it holds — see `refreshCatalogue`. The bundled copy
    /// is the floor under both: it keeps the picker full on a first launch
    /// before the network is up.
    var kotekans: [Kotekan] = Kotekan.bundled
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
    ///
    /// Remembered across launches, like the judging settings: they are toggled
    /// from the practice screen's Voices menu now, and a choice that quietly
    /// reset every launch read as the menu not working.
    var partnerAudible: Bool = Defaults.bool("partnerAudible", false) {
        didSet { Defaults.set("partnerAudible", partnerAudible) }
    }

    var yourVoiceAudible: Bool = Defaults.bool("yourVoiceAudible", true) {
        didSet { Defaults.set("yourVoiceAudible", yourVoiceAudible) }
    }

    /// How much the practice screen shows of where to damp: the hand tile
    /// behind each note and the pinch on the bar as the note ends. All of it
    /// by default — damping is half of playing a gangsa. Set in the Gangsa
    /// card and from the pause screen, and read live, so a change while
    /// paused shows on resume. Display only; damping is never judged.
    ///
    /// Was a Bool, `showsDamp`; a stored "off" carries over.
    ///
    /// ponytail: one setting for the app, not one per gangsa, though it sits
    /// in the Gangsa card. Nothing yet needs a different answer per gangsa.
    var dampGuide: DampGuide = .init(rawValue: Defaults.string("dampGuide") ?? "")
        ?? (Defaults.bool("showsDamp", true) ? .all : .off)
    {
        didSet { Defaults.set("dampGuide", dampGuide.rawValue) }
    }

    /// Whether the practice screen's bottom panel — the half switch, the tempo,
    /// the voice chips and the score — is up.
    ///
    /// DOWN by default. The guidance you play from is the bilah lighting up on
    /// the gangsa in front of you; the score is peripheral context, and the
    /// panel sits over exactly the part of the frame the instrument is most
    /// likely to be in. It is one tap away in the top bar for when it is wanted.
    var bottomBarVisible: Bool = false
    var lastResult: SongResult?
    /// `lastResult` is the made-up session from Settings → Debug, so the
    /// results screen shows a canned overview instead of asking the model.
    var lastResultIsSample = false
    /// What the figure's record was BEFORE the session that just ended, and
    /// whether that session beat it. Read by the results screen; set by
    /// `finish`, which is the only place that can tell, because filing the new
    /// record destroys the old one.
    var previousRecord: Double?
    var lastSetRecord = false

    /// Practice-mode tempo (§5.3): 0.5, 0.75, 1.0
    var tempoScale: Double = 1.0

    // R Judging settings (timing leniency, score wrong bars, call each stroke)
    // R lived here, set from a Judging card in Settings. The card went: the
    // R session counts the beat in and the kajar keeps it, and nobody tuned
    // R them. Their defaults are now fixed on `PlayEngine`.

    /// A sighting the microphone did not hear is discarded. See `DetectionMode`.
    ///
    /// PERSISTED, and it did not used to be — which made the detection mode
    /// silently reset to "Heard only" on any calibrated instrument. It was a
    /// plain stored property re-derived from `hasLearnedBaseline` in three
    /// places, so a learned baseline (permanent, once captured) re-imposed the
    /// microphone veto on every launch and every instrument switch, and nothing
    /// chosen on the detection screen survived either.
    ///
    /// The distinction that was missing: a baseline makes the veto POSSIBLE, so
    /// it is a sensible default the first time. It is not a decision, and it
    /// must not overwrite one. Below, `hasLearnedBaseline` may still clamp this
    /// OFF — an instrument with no baseline cannot veto on sound at all — but it
    /// may never turn it back on.
    ///
    /// This mattered more than a stale toggle: both the marker path and the
    /// vision self-trigger honour this flag, so every session spent testing
    /// camera-only detection was quietly running with the microphone holding a
    /// veto over it.
    var requireStrikeSound: Bool = Defaults.bool("requireStrikeSound", false) {
        didSet { Defaults.set("requireStrikeSound", requireStrikeSound) }
    }

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

    /// How far the vision score must fall from its own peak before the same
    /// bilah can register again.
    ///
    /// The double-note control, and the reason repeated strokes go missing in
    /// camera-only mode. The classifier is a PRESENCE detector: it reports that
    /// the mallet is over the bar, which stays true through the small bounce
    /// between two strokes on one bilah. The score dips a little and the
    /// Schmitt trigger never re-arms, so the second stroke is never seen.
    ///
    /// Lowering this is the only lever the classifier path has. It trades
    /// against double-firing on a single stroke, so it cannot go far — which is
    /// why the mode that pairs the camera with the microphone exists at all, and
    /// why the marker path (which times an impact rather than a presence) does
    /// not need this number.
    var visionRelativeDip: Double = Defaults.double("visionRelativeDip", 0.12) {
        didSet { Defaults.set("visionRelativeDip", visionRelativeDip) }
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

    /// Whether a chosen kotekan plays in the top view — the camera looking down
    /// on the real bilah — instead of the waterfall. Off by default: adding a
    /// gangsa no longer frames or aligns the keys, so the camera overlay would
    /// sit on the default layout rather than the instrument. Kept behind the
    /// Settings "Deprecated" card for anyone who still realigns by hand.
    var topView: Bool = Defaults.bool("topView", false) {
        didSet { Defaults.set("topView", topView) }
    }

    /// The three ways the two sensors can be arranged, as one choice instead of
    /// two booleans whose interaction nobody could predict from their names.
    enum DetectionMode: String, CaseIterable, Identifiable {
        case cameraOnly
        case cameraAndMic
        case heardOnly

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .cameraOnly: "Camera"
            case .cameraAndMic: "Camera + mic"
            case .heardOnly: "Heard only"
            }
        }

        var detail: String {
            switch self {
            case .cameraOnly:
                "Camera only. Best in a loud room."
            case .cameraAndMic:
                "Either can register a stroke. Catches repeated strokes best."
            case .heardOnly:
                "Both must agree. Use this if strokes register that you didn't play."
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

    /// Detect the mallet by its retroreflective marker instead of by the CNN.
    var markerVision: Bool = Defaults.bool("markerVision", false) {
        didSet { Defaults.set("markerVision", markerVision) }
    }

    /// Where the phone is looking from. Index into `MarkerPOV`.
    var markerPOV: Int = Defaults.int("markerPOV", MarkerPOV.top.rawValue) {
        didSet { Defaults.set("markerPOV", markerPOV) }
    }

    /// Front-view band geometry — the x extent the bilah span, a bulge term for
    /// a phone set down off-axis, and which end key 0 is at.
    var markerBandLeft: Double = Defaults.double("markerBandLeft", 0.05) {
        didSet { Defaults.set("markerBandLeft", markerBandLeft) }
    }

    var markerBandRight: Double = Defaults.double("markerBandRight", 0.95) {
        didSet { Defaults.set("markerBandRight", markerBandRight) }
    }

    var markerBandSkew: Double = Defaults.double("markerBandSkew", 0) {
        didSet { Defaults.set("markerBandSkew", markerBandSkew) }
    }

    var markerBandFlip: Bool = Defaults.bool("markerBandFlip", false) {
        didSet { Defaults.set("markerBandFlip", markerBandFlip) }
    }

    /// Ignore everything above this fraction of the frame.
    var markerROITop: Double = Defaults.double("markerROITop", 0) {
        didSet { Defaults.set("markerROITop", markerROITop) }
    }

    /// The marker vouches for the CLASSIFIER's sighting instead of replacing it.
    var requireMarker: Bool = Defaults.bool("requireMarker", false) {
        didSet { Defaults.set("requireMarker", requireMarker) }
    }

    /// How far outside a bilah the marker may sit and still vouch for it.
    var markerGateMargin: Double = Defaults.double("markerGateMargin", 0.06) {
        didSet { Defaults.set("markerGateMargin", markerGateMargin) }
    }

    /// Which colour tape is on the mallet. Index into `MarkerColour`.
    var markerColour: Int = Defaults.int(
        "markerColour",
        MarkerColour.red.rawValue
    ) {
        didSet { Defaults.set("markerColour", markerColour) }
    }

    /// Brightness, 0–255, that a pixel's BRIGHTEST CHANNEL must reach to be marker.
    var markerBrightness: Double = Defaults.double("markerBrightness", 235) {
        didSet { Defaults.set("markerBrightness", markerBrightness) }
    }

    /// How far a coloured marker's channel must lead the other two.
    var markerSaturationFloor: Double = Defaults.double(
        "markerSaturationFloor",
        60
    ) {
        didSet { Defaults.set("markerSaturationFloor", markerSaturationFloor) }
    }

    /// Stops below metered exposure while marker vision is on. Negative.
    var markerExposureBias: Double = Defaults.double("markerExposureBias", -2.5) {
        didSet { Defaults.set("markerExposureBias", markerExposureBias) }
    }

    /// Colour spread, 0–255, a bright pixel may have and still be marker.
    var markerSaturation: Double = Defaults.double("markerSaturation", 70) {
        didSet { Defaults.set("markerSaturation", markerSaturation) }
    }

    /// How far past the head marker the striking point sits.
    var markerTipExtension: Double = Defaults.double("markerTipExtension", 0.35) {
        didSet { Defaults.set("markerTipExtension", markerTipExtension) }
    }

    /// How fast the tip must be travelling before its turnaround counts as a strike.
    var markerMinSpeed: Double = Defaults.double("markerMinSpeed", 0.004) {
        didSet { Defaults.set("markerMinSpeed", markerMinSpeed) }
    }

    /// Index into the fill/centre/fit options.
    var cropScaleMode: Int = Defaults.int("cropScaleMode", 1) {
        didSet { Defaults.set("cropScaleMode", cropScaleMode) }
    }

    /// The phone is on a stand or arm rather than in someone's hand.
    var fixedMount: Bool = false

    /// Whether the gangsa's strike-sound baseline has been learned this session.
    var baselineLearned: Bool = false

    // MARK: - Contextual Guides & Onboarding

    enum Guide: String, CaseIterable, Identifiable {
        case app
        case kotekan
        case mekarBhuana
        case sensor
        case sensorCheck

        var id: String {
            rawValue
        }

        var seenKey: String {
            self == .app ? "hasSeenGuide" : "hasSeenGuide.\(rawValue)"
        }
    }

    var visibleGuide: Guide?
    var seen: Set<String> = Set(
        Guide.allCases.filter { Defaults.bool($0.seenKey, false) }
            .map(\.rawValue)
    )

    var showingOnboarding = false
    var hasSeenOnboarding = Defaults.bool("hasSeenOnboarding", false)

    var hasSeenPracticeCoach = Defaults.bool(
        "hasSeenPracticeCoach",
        false
    )

    // MARK: - Setup & Calibration Geometry

    var isAddingNewInstrument = false
    var previousProfile: InstrumentProfile?

    /// The area the player framed the instrument into (step 2/4), normalised.
    var framedRegion = NormalizedRect(x: 0, y: 0.17, w: 1, h: 0.68)
    var seedMasksFromFraming = false

    // MARK: - Strike controller (§3.6)

    /// Where the controller setup goes back to: Settings, or the kotekan
    /// picker when it was offered at the end of setting up a new gangsa.
    var controllerSetupReturn: Route = .settings
    /// Opened as the optional last step of a new gangsa — "Skip" rather than
    /// "Back", and nothing is lost by taking it.
    var controllerSetupIsOffer = false
    /// Opened straight onto the key check (Settings → "Check keys", or the
    /// re-check banner) instead of the scan.
    var controllerSetupRecheck = false
    /// Set when a new gangsa's alignment is confirmed, spent when its setup
    /// lands — see `finishSetup`.
    var offerControllerAfterSetup = false
    /// Note capture opened as the step before the controller offer: "Skip"
    /// rather than "Back", and closing it moves on instead of to Settings.
    var noteCaptureIsSetup = false

    // MARK: - Account

    /// Nil until the welcome screen's choice is made. Persisted, so the choice
    /// is asked once — and again only after signing out or a data reset.
    /// Read in `init`, after the data reset has had its chance to clear it.
    var account: Account?
    /// The label for the busy scrim while a sign-in is in flight.
    var accountBusy: String?
    var accountError: String?
    /// Set when a guest tries to link an Apple ID that already has an account;
    /// Settings asks before `confirmSwitch` drops this phone's progress.
    var pendingSwitch: AuthRepository.AccountExists?
    /// The profile an Apple account carries. Nil for guests.
    var playerName: String?
    var playerAvatar: Avatar?
    /// Where the profile step goes when it is done: Settings when it was
    /// opened from there, nil to carry on into the app.
    var profileReturn: Route?
    /// The screen a guest started linking from, for after a switch.
    var linkOrigin: Route?
    /// The one-time "keep your progress" prompt on the results screen.
    var showingSavePrompt = false

    // MARK: - Remote Repositories

    @ObservationIgnored let auth = Container.shared.authRepository()
    /// The figure Create Kotek opens on, or nil for a new one. Read once, when
    /// the screen builds its draft.
    var editingKotekan: Kotekan?
    /// One-screen coop's players. Kept between sessions, so a pair who play
    /// again do not type their names twice; nil until coop is first opened.
    var coop: CoopSetup?
    /// The picker's Solo / Co-op. Held here, not in the picker, so coming back
    /// from the coop setup finds it still on Co-op; every launch starts solo.
    var playMode: PlayMode = .solo
    /// Where Learn is, while it runs; nil otherwise.
    var learnStage: LearnStage?
    /// The splash is up and drawing its own gangsa over the landing screen's.
    /// The landing screen holds its copy still meanwhile — two animated
    /// gangsa, one hidden, on the busiest seconds of launch.
    var splashCovering = true

    @ObservationIgnored let instrumentRemote = Container.shared
        .instrumentRemoteRepository()
    @ObservationIgnored let kotekanRepo = Container.shared.kotekanRepository()
    @ObservationIgnored let sessionRepo = Container.shared
        .practiceSessionRepository()
    @ObservationIgnored let log = Logger(subsystem: "Kotek", category: "remote")
    @ObservationIgnored let sensor = Container.shared.sensorService()
    @ObservationIgnored let cue = Container.shared.cueService()

    // MARK: - Initialization

    init() {
        Self.resetLocalDataIfStale()
        if let cached = KotekanStore.load(), !cached.isEmpty { kotekans = cached }
        let all = ProfileStore.loadAll()
        MalletHitClassifier.applyCropScale(
            mode: Defaults.int("cropScaleMode", 1)
        )
        savedProfiles = all
        if let current = ProfileStore.loadSelected() {
            profile = current
            baselineLearned = current.hasLearnedBaseline
            if !Defaults.has("requireStrikeSound") {
                requireStrikeSound = current.hasLearnedBaseline
            } else if !current.hasLearnedBaseline {
                requireStrikeSound = false
            }
        } else {
            profile = ResourceLoader.defaultProfile()
        }
        screen = .welcome
        // didSet does not fire inside init
        playsRecordedSounds = Self.playsRecordedSounds(profile.id)
        applyKeySounds()

        account = Defaults.string("account").flatMap(Account.init)
        if account == .apple { loadPlayer() }
        if account != nil { startSync() }
        #if DEBUG
            applyScreenshotScene()
        #endif
    }

    // MARK: - Screen Navigation

    /// Same figure again, on whichever play screen `topView` picks — the
    /// waterfall counts itself in, so it has no countdown route.
    func retry() {
        screen = topView ? .countdown : .waterfall
    }

    func backToKotekan() {
        screen = .chooseKotekan
    }

    func openCreateKotek() {
        editingKotekan = nil
        screen = .createKotek
    }

    /// Create Kotek, opened on one of the player's own figures. Saving keeps
    /// its id, so the row is updated in place rather than duplicated.
    func openEditKotek(_ k: Kotekan) {
        guard k.source != .builtin else { return }
        editingKotekan = k
        screen = .createKotek
    }

    func openSettings() {
        screen = .settings
    }

    func closeSettings() {
        screen = .chooseKotekan
    }

    func openHistory() {
        screen = .history
    }

    func closeHistory() {
        screen = .settings
    }

    func openCalibration() {
        screen = .calibrating
    }

    func calibrationFinished() {
        screen = .chooseKotekan
    }

    func openBaseline() {
        screen = .baseline
    }

    func openMalletTest() {
        screen = .malletTest
    }

    func closeMalletTest() {
        screen = .settings
    }

    func openDetectionTest() {
        screen = .detectionTest
    }

    func openCaptureTraining() {
        screen = .captureTraining
    }

    func closeCaptureTraining() {
        screen = .settings
    }

    func closeDetectionTest() {
        screen = .settings
    }

    func openNoteCapture(setup: Bool = false) {
        noteCaptureIsSetup = setup
        screen = .noteCapture
    }

    func closeNoteCapture() {
        guard noteCaptureIsSetup else {
            screen = .settings
            return
        }
        noteCaptureIsSetup = false
        openControllerSetup(returnTo: .chooseKotekan, offer: true)
    }

    /// Back from setup's note capture to the key count. Still mid-add, so
    /// confirming runs the same hand-off again and cancelling discards it.
    func backToKeyCount() {
        noteCaptureIsSetup = false
        screen = .choosingKeyCount
    }

    func openAudioTest() {
        screen = .audioTest
    }

    func closeAudioTest() {
        screen = .settings
    }

    func openSensorTest() {
        screen = .sensorTest
    }

    func closeSensorTest() {
        screen = .settings
    }

    /// The persistent re-alignment affordance (§13.4).
    func realign() {
        screen = .aligning
    }
}

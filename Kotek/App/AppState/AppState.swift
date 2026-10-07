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
    var profile: InstrumentProfile
    var savedProfiles: [InstrumentProfile] = []

    // The kotekan session carried through selection → play.
    /// The bundled catalogue until Supabase answers, then whatever it holds —
    /// see `refreshCatalogue`. Starting from the bundled copy is what keeps the
    /// picker full offline and on a first launch before the network is up.
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

    /// Practice-mode tempo (§5.3): 0.5, 0.75, 1.0
    var tempoScale: Double = 1.0
    // Audio cue toggles (§5.4)
    var metronomeEnabled: Bool = true
    var referenceToneEnabled: Bool = true

    /// Whether a stroke on a bilah nothing is due on may take the note that is
    /// due, scored as a wrong bar. See `PlayEngine.scoresWrongBar` for why this
    /// defaults off — in camera-only mode it is how a travelling mallet destroys
    /// a note the player then plays correctly.
    var scoresWrongBar: Bool = Defaults.bool("scoresWrongBar", false) {
        didSet { Defaults.set("scoresWrongBar", scoresWrongBar) }
    }

    /// Whether each stroke's verdict is called on the bilah as it happens.
    ///
    /// On by default because without it a miss is INVISIBLE on the instrument —
    /// see `PlayEngine.Floater`. Off restores the wordless overlay the guidance
    /// layer was designed around.
    var callsStrokes: Bool = Defaults.bool("callsStrokes", true) {
        didSet { Defaults.set("callsStrokes", callsStrokes) }
    }

    /// How forgiving the timing grades are. 1.0 is the figure as notated.
    ///
    /// Deliberately affects the GRADE and not whether a stroke registers. When
    /// notes go missing entirely that is a matching problem, not a strictness
    /// one, and reaching for this dial to fix it only hides it — see the note
    /// on the matcher in `PlayEngine.registerPlayStrike`.
    var judgementLeniency: Double = Defaults.double("judgementLeniency", 1.25) {
        didSet { Defaults.set("judgementLeniency", judgementLeniency) }
    }

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
                "The microphone is ignored, so nothing in the room can trigger a stroke or block one. Use this in a loud hall — a mallet that hovers over a bar can still register."
            case .cameraAndMic:
                "Either can register a stroke. The most willing of the three, and the microphone is what catches a bar struck twice in a row, which the camera cannot see."
            case .heardOnly:
                "A stroke counts only where the camera sees one and the microphone hears the attack. Use this when strokes register that you did not play."
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

    // MARK: - Remote Repositories

    @ObservationIgnored let instrumentRemote = Container.shared.instrumentRemoteRepository()
    @ObservationIgnored let kotekanRepo = Container.shared.kotekanRepository()
    @ObservationIgnored let sessionRepo = Container.shared.practiceSessionRepository()
    @ObservationIgnored let log = Logger(subsystem: "Kotek", category: "remote")

    // MARK: - Initialization

    init() {
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

        let pending = all
        Task {
            await refreshCatalogue()
            for p in pending {
                await push(p)
            }
        }
    }

    // MARK: - Screen Navigation

    func retry() {
        screen = .countdown
    }

    func backToKotekan() {
        screen = .chooseKotekan
    }

    func openSettings() {
        screen = .settings
    }

    func closeSettings() {
        screen = .chooseKotekan
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

    func openAudioTest() {
        screen = .audioTest
    }

    func closeAudioTest() {
        screen = .settings
    }

    /// The persistent re-alignment affordance (§13.4).
    func realign() {
        screen = .aligning
    }
}

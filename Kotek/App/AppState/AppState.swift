//
//  AppState.swift
//  Kotek
//
//  The app-level state machine (PRD §13.4). Adding a gangsa runs in three
//  steps — count the keys, record each bilah, set up the strike controller —
//  and lands on the kotekan picker. (It was four camera steps — count, frame,
//  fit the mask, learn the voice — with a "realign" back to the mask from
//  anywhere; the camera play mode went in November 2026.)
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

    // R The detector's settings lived here — the strike-sound veto, vision
    // R thresholds, the marker tracker's two dozen knobs, the camera mount, the
    // R learned-baseline flag, and `topView`, which sent a chosen kotekan to
    // R the camera overlay instead of the waterfall. All of it tuned the
    // R camera play mode, which went in November 2026.

    // MARK: - Contextual Guides & Onboarding

    enum Guide: String, CaseIterable, Identifiable {
        case app
        case kotekan
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
    /// The landing's music bed held silent while something else is sounding
    /// over it: the onboarding's interlock sample. `WelcomeView` owns the bed.
    var musicHushed = false
    var hasSeenOnboarding = Defaults.bool("hasSeenOnboarding", false)

    // MARK: - Adding a gangsa

    var isAddingNewInstrument = false
    var previousProfile: InstrumentProfile?

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
    /// Note capture opened as the step before the controller offer: "Skip"
    /// rather than "Back", and closing it moves on instead of to Settings.
    var noteCaptureIsSetup = false
    /// Where closing note capture goes outside setup: Settings, or the gangsa
    /// picker when it was opened from a card's menu.
    var noteCaptureReturn = Route.settings
    /// Where Done in Settings goes; see `openSettings`.
    var settingsReturn = Route.chooseKotekan

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
    /// Learn was just finished, into free play: Kipli says so as it opens.
    /// Taken (set back) by the free play screen that reads it.
    var justLearned = false
    /// The splash is up and its gate has not started to open. Meanwhile the
    /// landing screen holds its gangsa still — an animated gangsa nobody can
    /// see, on the busiest seconds of launch — and draws itself as if from a
    /// little way off (`WelcomeView.zoom`). Lifted inside the gate's opening
    /// animation, so both start with it.
    var splashCovering = true
    /// The splash's gate has finished opening, and the landing screen may
    /// draw its own. Not before: while the camera walks up to the gate, the
    /// landing screen's copy, inside a scaling view, was drawn stale — small,
    /// stood still, inside the splash's opening — until the splash went.
    /// Drawn from here on, it is drawn once, at rest, exactly under the
    /// splash's final frame.
    var splashGateOpen = false

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
        savedProfiles = all
        if let current = ProfileStore.loadSelected() {
            profile = current
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

    /// Same figure again. The waterfall counts itself in, so it has no
    /// countdown route.
    func retry() {
        screen = .waterfall
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

    /// Done goes back to the picker Settings was opened from: the gangsa
    /// picker has its own gear now, and Done from there used to land on the
    /// kotekan picker instead. Anywhere else (a Shortcut) still goes there.
    func openSettings() {
        settingsReturn = screen == .chooseInstrument ? .chooseInstrument : .chooseKotekan
        screen = .settings
    }

    func closeSettings() {
        screen = settingsReturn
    }

    func openHistory() {
        screen = .history
    }

    func closeHistory() {
        screen = .settings
    }

    func openNoteCapture(setup: Bool = false, returnTo: Route = .settings) {
        noteCaptureIsSetup = setup
        noteCaptureReturn = returnTo
        screen = .noteCapture
    }

    func closeNoteCapture() {
        guard noteCaptureIsSetup else {
            screen = noteCaptureReturn
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

    func openSensorTest() {
        screen = .sensorTest
    }

    func closeSensorTest() {
        screen = .settings
    }
}

//
//  NoteCaptureViewModel.swift
//  Kotek
//
//  Drives the hands-free run through the gangsa: arm the mic for one bilah, wait
//  for the strike, hand the samples to NoteClipCapture off the main actor, then
//  move to the next bilah without a clip. Also owns the bilah card: what a
//  recorded key sounds like, and redoing it.
//
//  It was one take per tap: Record, stay quiet, "Strike now", then a second to
//  do it. Fine with a finger on the screen; not for someone holding a panggul
//  and looking at the instrument.
//

import AVFoundation
import FactoryKit
import Foundation
import Observation

@Observable
@MainActor
final class NoteCaptureViewModel {
    enum Phase: Equatable {
        case idle
        /// Armed, waiting for the strike.
        case listening
        /// Heard it; taking the rest of the note.
        case ringing
        case processing
    }

    /// Few and chunky: they are drawn in the bilah card.
    private nonisolated static let savedBins = 24
    /// A take under this share of the session's median peak gets Kipli's "a bit
    /// quiet". Relative, because the phone's distance from the gangsa moves
    /// every peak together.
    /// ponytail: 0.4 is a starting point, retune on a real gangsa.
    private static let quietShare: Float = 0.4

    private let app: AppState
    let audio: AudioEngineController

    var phase: Phase = .idle
    /// The key being listened for; see `currentKey` for what the tiles show.
    private(set) var keyIndex: Int
    /// Keys that have a saved clip.
    var keysWithClips: Set<Int> = []
    /// The key whose card is open. The mic is off while it is: a clip played
    /// through the speaker would reach it and count as a strike.
    private(set) var inspected: Int?
    var isPlaying = false
    /// Peaks of the inspected key's saved clip (empty if it has none).
    var waveform: [Float] = []
    /// What just went wrong, said by Kipli until the next strike.
    private var failure: String?
    /// This session's takes, before normalising. Session-only: a clip that came
    /// from an earlier visit has no flag to show.
    private var peaks: [Int: Float] = [:]
    /// Carry on to the next key without a clip after this take. Off for a
    /// redo from the review, which ends where it began.
    private var runsOn = false
    /// Bumped whenever a take is dropped, so a capture's late callback can tell
    /// it no longer counts: `cancelCapture` can't recall one already on its way.
    private var take = 0

    private var player: AVAudioPlayer?
    private var playbackTask: Task<Void, Never>?

    init(app: AppState, audio: AudioEngineController = Container.shared.audioService()) {
        self.app = app
        self.audio = audio
        keyIndex = app.profile.keys.first?.index ?? 0
        let instrumentID = app.profile.id
        keysWithClips = Set(app.profile.keys.map(\.index).filter {
            NoteClipCapture.latestClip(instrumentID: instrumentID, keyIndex: $0) != nil
        })
    }

    /// What the user sees as the key's name; `keyIndex` stays 0-based because
    /// that is what the filenames and everything else in the app use.
    static func number(for keyIndex: Int) -> Int {
        keyIndex + 1
    }

    var isListening: Bool {
        phase != .idle
    }

    /// Every bilah has a clip and nothing is going on: "Have a listen".
    var isReview: Bool {
        !isListening && nextKey == nil
    }

    /// The tile that is up: the one being listened for, or the one that will be.
    var currentKey: Int? {
        isListening ? keyIndex : nextKey
    }

    private var keyIndices: [Int] {
        app.profile.keys.map(\.index)
    }

    private var nextKey: Int? {
        keyIndices.first { !keysWithClips.contains($0) }
    }

    /// Takes that came out soft, once the run is over. Needs a few to compare.
    var quietKeys: [Int] {
        guard !isListening, peaks.count >= 3 else { return [] }
        let median = peaks.values.sorted()[peaks.count / 2]
        return keyIndices.filter { (peaks[$0] ?? .infinity) < median * Self.quietShare }
    }

    var kipliLine: LocalizedStringResource {
        if let failure { return LocalizedStringResource(stringLiteral: failure) }
        switch phase {
        case .listening:
            return "One hit, normal strength. I'm listening."
        case .ringing, .processing:
            return "Got it. Let it ring…"
        case .idle:
            guard isReview else {
                return "Find a quiet spot, then just hit the real bilah.\nNo need to touch the screen."
            }
            if let quiet = quietKeys.first {
                return "Bilah \(Self.number(for: quiet)) was a bit quiet.\nTap any bilah to hear it again."
            }
            return "They all sound good.\nTap any bilah to hear it again."
        }
    }

    var kipliMood: KipliGuide.Mood {
        failure == nil ? .happy : .sad
    }

    var playbackProgress: Double {
        guard isPlaying, let player, player.duration > 0 else { return 0 }
        return min(1, player.currentTime / player.duration)
    }

    func start() {
        try? audio.start(profile: app.profile)
    }

    func teardown() {
        stopPlayback()
        dropTake()
        runsOn = false
        phase = .idle
        audio.stop()
    }

    // MARK: Listening

    func startListening() {
        guard let nextKey else { return }
        stopPlayback()
        failure = nil
        runsOn = true
        keyIndex = nextKey
        arm()
    }

    /// Record this key again. Mid-run, the run carries on afterwards.
    func redo(_ key: Int) {
        guard phase == .idle || phase == .listening else { return }
        stopPlayback()
        inspected = nil
        failure = nil
        dropTake()
        keyIndex = key
        arm()
    }

    private func dropTake() {
        take += 1
        audio.cancelCapture()
    }

    private func arm() {
        guard AudioSessionManager.recordAuthorized else {
            stop(because: String(localized: "Microphone access is off. Turn it on in Settings."))
            return
        }
        guard audio.isRunning else {
            stop(because: String(localized: "Audio isn't ready. Try again."))
            return
        }
        phase = .listening
        take += 1

        let current = take
        let key = keyIndex
        let instrumentID = app.profile.id
        let gate = audio.gateSettings().floor
        audio.listenForStrike(
            lead: NoteClipCapture.takeLeadSeconds,
            tail: NoteClipCapture.takeTailSeconds,
            onHeard: { [weak self] in
                guard let self, take == current else { return }
                failure = nil
                phase = .ringing
            },
            completion: { [weak self] samples, rate in
                Task {
                    await self?.finish(
                        samples, rate: rate, key: key, instrumentID: instrumentID, gate: gate, take: current
                    )
                }
            }
        )
    }

    private func stop(because reason: String) {
        failure = reason
        runsOn = false
        phase = .idle
    }

    private func finish(
        _ samples: [Float], rate: Double, key: Int, instrumentID: String, gate: Float, take current: Int
    ) async {
        guard take == current else { return }
        phase = .processing
        let result = await Task.detached(priority: .utility) {
            Result {
                let clip = try NoteClipCapture.extract(from: samples, sampleRate: rate, strikeGate: gate)
                let url = try NoteClipCapture.save(clip, instrumentID: instrumentID, keyIndex: key, sampleRate: rate)
                return (url: url, peak: clip.peak)
            }
        }.value
        switch result {
        case let .success(saved):
            app.setSound(saved.url.lastPathComponent, forKey: key)
            keysWithClips.insert(key)
            peaks[key] = saved.peak
        case let .failure(error):
            failure = error.localizedDescription
        }
        // Left the screen while that was saving: the take is kept, the run isn't.
        guard take == current else { return }
        if case .failure = result {
            arm()
        } else if runsOn, let nextKey {
            keyIndex = nextKey
            arm()
        } else {
            runsOn = false
            phase = .idle
        }
    }

    // MARK: The bilah card

    /// Open a recorded key's card, playing it. Not while a take is coming in:
    /// the strike has been heard, and the card would throw it away.
    func inspect(_ key: Int) {
        guard keysWithClips.contains(key), phase == .idle || phase == .listening else { return }
        dropTake()
        inspected = key
        waveform = []
        refreshWaveform(key)
        togglePlayback()
    }

    func closeCard() {
        stopPlayback()
        inspected = nil
        if phase == .listening { arm() }
    }

    func deleteRecording() {
        guard let key = inspected else { return }
        NoteClipCapture.deleteClips(instrumentID: app.profile.id, keyIndex: key)
        app.setSound(nil, forKey: key)
        keysWithClips.remove(key)
        peaks[key] = nil
        closeCard()
    }

    func togglePlayback() {
        if isPlaying {
            stopPlayback()
            return
        }
        guard let key = inspected,
              let clip = NoteClipCapture.latestClip(instrumentID: app.profile.id, keyIndex: key)
        else {
            failure = String(localized: "Couldn't play the clip.")
            return
        }
        failure = nil
        // Shows "Stop" at once; stopPlayback() cancels the task below.
        isPlaying = true
        playbackTask = Task {
            // AVAudioPlayer activates the shared session on whatever thread
            // starts it, and activation can block (route changes, other apps).
            // Do it here, off the main actor, so play() finds it already active.
            // The async `activate` API is iOS 27+; the target is 26.5.
            await AudioSessionManager.configure()
            guard !Task.isCancelled else { return }
            guard let player = try? await Self.makePlayer(url: clip), !Task.isCancelled else {
                isPlaying = false
                if !Task.isCancelled { failure = String(localized: "Couldn't play the clip.") }
                return
            }
            self.player = player
            player.play()
            try? await Task.sleep(for: .seconds(player.duration))
            if !Task.isCancelled { isPlaying = false }
        }
    }

    @concurrent
    private static func makePlayer(url: URL) async throws -> sending AVAudioPlayer {
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        return player
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        player?.stop()
        isPlaying = false
    }

    private func refreshWaveform(_ key: Int) {
        let instrumentID = app.profile.id
        Task {
            let peaks = await Task.detached(priority: .utility) { () -> [Float] in
                guard let url = NoteClipCapture.latestClip(instrumentID: instrumentID, keyIndex: key) else { return [] }
                return NoteClipCapture.waveform(of: url, bins: Self.savedBins)
            }.value
            if inspected == key { waveform = peaks }
        }
    }
}

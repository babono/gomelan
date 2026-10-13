//
//  NoteCaptureViewModel.swift
//  Kotek
//
//  Drives one note-clip take: ask for quiet, open the raw capture, prompt the
//  strike, then hand the samples to NoteClipCapture off the main actor. Also
//  owns key selection, the waveform shown for the selected key, and replay.
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
        case quiet
        case strike
        case processing
    }

    /// Slots in the live waveform; each buffer's peak lands in the slot for how
    /// far through the take it arrived.
    nonisolated static let liveSlots = 120
    private nonisolated static let savedBins = 120

    private let app: AppState
    let audio: AudioEngineController

    var phase: Phase = .idle
    var keyIndex: Int
    /// Last outcome, success or failure, shown under the graph.
    var message: String?
    /// Keys that have at least one saved clip; Play replays the newest for the selected key.
    var keysWithClips: Set<Int> = []
    var isPlaying = false
    /// Peaks of the selected key's newest saved clip (empty if it has none).
    var waveform: [Float] = []
    /// Peaks of the take in progress.
    var liveLevels: [Float] = []

    private var player: AVAudioPlayer?
    private var playbackTask: Task<Void, Never>?

    /// How long the user must stay silent before the "strike now" prompt.
    private let quietSeconds = NoteClipCapture.strikePromptSeconds

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
    static func number(for keyIndex: Int) -> Int { keyIndex + 1 }

    var isRecording: Bool { phase != .idle }

    var statusText: String {
        switch phase {
        case .idle:
            keysWithClips.contains(keyIndex)
                ? "Key \(Self.number(for: keyIndex)) recorded"
                : "Key \(Self.number(for: keyIndex)) not recorded"
        case .quiet: "Quiet…"
        case .strike: "Strike now"
        case .processing: "Processing…"
        }
    }

    private var keyIndices: [Int] { app.profile.keys.map(\.index) }

    var hasNext: Bool {
        keysWithClips.contains(keyIndex) && keyIndices.last != keyIndex
    }

    var playbackProgress: Double {
        guard isPlaying, let player, player.duration > 0 else { return 0 }
        return min(1, player.currentTime / player.duration)
    }

    func start() {
        try? audio.start(profile: app.profile)
        audio.onRawLevel = { [weak self] peak, progress in
            self?.ingest(peak: peak, progress: progress)
        }
        refreshWaveform()
    }

    func teardown() {
        stopPlayback()
        audio.onRawLevel = nil
        audio.cancelCapture()
        audio.stop()
    }

    func select(_ index: Int) {
        guard !isRecording, index != keyIndex else { return }
        stopPlayback()
        keyIndex = index
        message = nil
        refreshWaveform()
    }

    func deleteRecording() {
        guard !isRecording else { return }
        stopPlayback()
        NoteClipCapture.deleteClips(instrumentID: app.profile.id, keyIndex: keyIndex)
        keysWithClips.remove(keyIndex)
        waveform = []
        message = "Recording deleted."
    }

    func next() {
        guard hasNext, let at = keyIndices.firstIndex(of: keyIndex) else { return }
        select(keyIndices[at + 1])
    }

    func togglePlayback() {
        if isPlaying {
            stopPlayback()
            return
        }
        guard let clip = NoteClipCapture.latestClip(instrumentID: app.profile.id, keyIndex: keyIndex) else {
            message = "Couldn't play the clip."
            return
        }
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
                if !Task.isCancelled { message = "Couldn't play the clip." }
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

    private func ingest(peak: Float, progress: Double) {
        guard liveLevels.count == Self.liveSlots else { return }
        let slot = min(Self.liveSlots - 1, Int(progress * Double(Self.liveSlots)))
        liveLevels[slot] = max(liveLevels[slot], peak)
    }

    private func refreshWaveform() {
        let key = keyIndex
        let instrumentID = app.profile.id
        Task {
            let peaks = await Task.detached(priority: .utility) { () -> [Float] in
                guard let url = NoteClipCapture.latestClip(instrumentID: instrumentID, keyIndex: key) else { return [] }
                return NoteClipCapture.waveform(of: url, bins: Self.savedBins)
            }.value
            if keyIndex == key { waveform = peaks }
        }
    }

    func record() {
        guard phase == .idle else { return }
        stopPlayback()
        guard AudioSessionManager.recordAuthorized else {
            message = "Microphone access is off. Enable it in Settings."
            return
        }
        guard audio.isRunning else {
            message = "Audio engine isn't running."
            return
        }
        message = nil
        liveLevels = [Float](repeating: 0, count: Self.liveSlots)
        phase = .quiet

        let key = keyIndex
        let instrumentID = app.profile.id
        let gate = audio.gateSettings().floor
        audio.captureRawSamples(duration: NoteClipCapture.takeSeconds) { [weak self] samples, rate in
            Task { await self?.finish(samples, rate: rate, key: key, instrumentID: instrumentID, gate: gate) }
        }
        Task {
            try? await Task.sleep(for: .seconds(quietSeconds))
            if phase == .quiet { phase = .strike }
        }
    }

    private func finish(_ samples: [Float], rate: Double, key: Int, instrumentID: String, gate: Float) async {
        phase = .processing
        let result = await Task.detached(priority: .utility) {
            Result {
                let clip = try NoteClipCapture.extract(from: samples, sampleRate: rate, strikeGate: gate)
                let url = try NoteClipCapture.save(clip, instrumentID: instrumentID, keyIndex: key, sampleRate: rate)
                return (url: url, endsRinging: clip.endsRinging)
            }
        }.value
        switch result {
        case .success(let saved):
            keysWithClips.insert(key)
            message = saved.endsRinging ? "Saved, but still ringing at the cut. Raise clipSeconds." : "Saved."
            refreshWaveform()
        case .failure(let error):
            message = error.localizedDescription
        }
        liveLevels = []
        phase = .idle
    }
}

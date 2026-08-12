//
//  PlayEngine.swift
//  gomelan
//
//  The core loop (PRD §4 Flow C, §5.1). Timing, judgement, overlay state and cue
//  triggering. Driven by tick(now:) from a TimelineView(.animation) so timing is
//  frame-accurate (§13.5).
//
//  Two modes (§5.3):
//   - .play     scored, timed, can miss
//   - .practice no fail, waits for the correct key before advancing
//

import SwiftUI
import QuartzCore

enum FlashKind: Equatable {
    case hitPerfect      // Green (exact right moment)
    case hitGood         // Orange / Terracotta (buffer okay)
    case wrongOrOffBeat  // Pale white (wrong key or off-beat)

    static var hit: FlashKind { .hitPerfect }
    static var miss: FlashKind { .wrongOrOffBeat }
    static var wrong: FlashKind { .wrongOrOffBeat }
}

/// What the overlay should draw for a single key this frame.
struct KeyRenderState: Equatable {
    var fill: Double = 0        // upcoming fill, 0…1 (§13.5 "fills from bottom")
    var strikeNow: Bool = false // solid highlight pulse
    var flash: FlashKind? = nil // transient hit/miss/wrong
    var damp: Bool = false      // dashed damp hint on the previous key (§5.5)
}

/// A note approaching on the bottom track (§13.5).
struct ApproachNote: Identifiable, Equatable {
    let id: String
    let keyIndex: Int
    let xFraction: Double       // 0…1 across the track; strike line at 0.15
}

@Observable
final class PlayEngine {

    // Rendering outputs
    private(set) var renderStates: [Int: KeyRenderState] = [:]
    private(set) var approachNotes: [ApproachNote] = []
    private(set) var currentTimeMs: Double = 0
    private(set) var isFinished = false

    // Live judgement feed (for debug / practice feedback)
    private(set) var lastJudgement: NoteJudgement?

    // Dependencies set before start
    var cue: CuePlayer?
    var metronomeEnabled = true
    var referenceToneEnabled = true
    var onComplete: ((SongResult?) -> Void)?
    /// "Kotekan Telu · Polos · 8×" — shown on the results screen.
    var sessionSubtitle = ""

    // Config
    private var song: Song = ResourceLoader.bundledSongs().first ?? Song(id: "", title: "", difficulty: .beginner, bpm: 60, requiredKeys: 0, durationMs: 0, notes: [])
    private var profile: InstrumentProfile?
    private var mode: PlayMode = .play
    private var tempoScale: Double = 1

    // Play-mode state
    private var notes: [Note] = []
    private var judged: [Bool] = []
    private var results: [NoteJudgement] = []
    private var referencedNotes: Set<String> = []
    private var lastBeatIndex = -1

    // Practice-mode state
    private(set) var practiceIndex = 0

    // Transient flash bookkeeping: keyIndex -> (kind, expiry host time)
    private var flashes: [Int: (FlashKind, Double)] = [:]

    private var startHostTime: Double = 0

    // Tunables
    private let approachWindowMs: Double = 1500          // upcoming fill lead-in
    private let missWindowMs: Double = 200               // §5.1
    private let flashDuration: Double = 0.3              // 300ms fades (§13.5)

    // MARK: - Lifecycle

    func configure(song: Song, mode: PlayMode, profile: InstrumentProfile, tempoScale: Double) {
        self.song = song
        self.mode = mode
        self.profile = profile
        self.tempoScale = mode == .practice ? max(0.25, tempoScale) : 1
        self.notes = song.notes.sorted { $0.timeMs < $1.timeMs }
        self.judged = Array(repeating: false, count: notes.count)
        self.results = []
        self.referencedNotes = []
        self.practiceIndex = 0
        self.lastBeatIndex = -1
        self.flashes = [:]
        self.isFinished = false
        self.renderStates = [:]
    }

    func start() {
        startHostTime = CACurrentMediaTime()
        cue?.start()
    }

    /// Shift the clock forward to absorb a pause (§13.4 .paused).
    func adjustStart(by seconds: Double) {
        startHostTime += seconds
    }

    private func scaledTime(_ note: Note) -> Double { Double(note.timeMs) / tempoScale }

    // MARK: - Frame tick

    func tick(now: Double) {
        guard !isFinished else { return }
        currentTimeMs = (now - startHostTime) * 1000

        var states: [Int: KeyRenderState] = [:]
        func ensure(_ i: Int) -> KeyRenderState { states[i] ?? KeyRenderState() }

        // Carry over live flashes.
        for (key, entry) in flashes {
            if now <= entry.1 {
                var s = ensure(key); s.flash = entry.0; states[key] = s
            }
        }
        flashes = flashes.filter { now <= $0.value.1 }

        switch mode {
        case .play:
            tickPlay(now: now, states: &states)
        case .practice:
            tickPractice(now: now, states: &states)
        }

        renderStates = states
        rebuildApproachTrack()
        checkCompletion(now: now)
    }

    private func tickPlay(now: Double, states: inout [Int: KeyRenderState]) {
        // Auto-miss notes whose window has fully passed.
        for i in notes.indices where !judged[i] {
            if currentTimeMs > scaledTime(notes[i]) + missWindowMs {
                judged[i] = true
                record(.miss, at: notes[i].keyIndex, now: now, playSound: true)
            }
        }

        // Upcoming fills + strike-now, plus reference-tone one beat ahead.
        let beatMs = 60000.0 / Double(song.bpm) / tempoScale
        for i in notes.indices where !judged[i] {
            let t = scaledTime(notes[i])
            let until = t - currentTimeMs
            let key = notes[i].keyIndex

            if until <= approachWindowMs && until >= -missWindowMs {
                var s = states[key] ?? KeyRenderState()
                let fill = 1 - max(0, until) / approachWindowMs
                s.fill = max(s.fill, min(1, fill))
                if abs(until) <= 60 { s.strikeNow = true }
                states[key] = s
            }

            // Reference tone one beat ahead (§5.4).
            if referenceToneEnabled, !referencedNotes.contains(notes[i].id),
               until <= beatMs, until > beatMs - 40 {
                referencedNotes.insert(notes[i].id)
                if let hz = profile?.keys.first(where: { $0.index == key })?.fundamentalHz {
                    cue?.playReference(hz: hz)
                }
            }
        }

        // Metronome on the beat (§5.4).
        if metronomeEnabled {
            let beatIndex = Int(currentTimeMs / beatMs)
            if beatIndex != lastBeatIndex, currentTimeMs >= 0 {
                lastBeatIndex = beatIndex
                cue?.playClick()
            }
        }
    }

    private func tickPractice(now: Double, states: inout [Int: KeyRenderState]) {
        guard practiceIndex < notes.count else { return }
        let note = notes[practiceIndex]

        // Expected key pulses.
        var s = states[note.keyIndex] ?? KeyRenderState()
        s.strikeNow = true
        s.fill = 1
        states[note.keyIndex] = s

        // Damp hint on the previous key (§5.5) — teach it, don't score it.
        if practiceIndex > 0 {
            let prev = notes[practiceIndex - 1].keyIndex
            var ps = states[prev] ?? KeyRenderState()
            ps.damp = true
            states[prev] = ps
        }
    }

    // MARK: - Strike handling (from AudioEngineController, main queue)

    func registerStrike(keyIndex: Int, hostTime: Double, confidence: Double) {
        guard !isFinished else { return }
        switch mode {
        case .play: registerPlayStrike(keyIndex: keyIndex, hostTime: hostTime)
        case .practice: registerPracticeStrike(keyIndex: keyIndex, hostTime: hostTime)
        }
    }

    private func registerPlayStrike(keyIndex: Int, hostTime: Double) {
        let atMs = (hostTime - startHostTime) * 1000

        // Nearest unjudged note in time within the miss window.
        var target: Int?
        var bestErr = missWindowMs
        for i in notes.indices where !judged[i] {
            let err = abs(scaledTime(notes[i]) - atMs)
            if err <= bestErr { bestErr = err; target = i }
        }
        guard let i = target else { return } // stray strike, ignore

        judged[i] = true
        let err = scaledTime(notes[i]) - atMs
        if notes[i].keyIndex == keyIndex {
            let result = JudgementResult.from(timingErrorMs: err)
            record(result, at: keyIndex, now: hostTime, playSound: true, timingErrorMs: err)
        } else {
            // Correct timing, wrong key: amber on struck key, correct stays lit.
            record(.wrongKey, at: keyIndex, now: hostTime, playSound: true, timingErrorMs: err)
        }
    }

    private func registerPracticeStrike(keyIndex: Int, hostTime: Double) {
        guard practiceIndex < notes.count else { return }
        let expected = notes[practiceIndex].keyIndex

        if keyIndex == expected {
            // Self-paced practice: hitting expected key is always a green hit!
            flash(.hitPerfect, at: keyIndex, now: hostTime)
            cue?.playHit()
            practiceIndex += 1
        } else {
            // Wrong key struck -> Pale White
            flash(.wrongOrOffBeat, at: keyIndex, now: hostTime)
        }
    }

    // MARK: - Helpers

    private func record(_ result: JudgementResult, at key: Int, now: Double, playSound: Bool, timingErrorMs: Double = 0, storeResult: Bool = true) {
        let judgement = NoteJudgement(keyIndex: key, result: result, timingErrorMs: timingErrorMs)
        if storeResult { results.append(judgement) }
        lastJudgement = judgement
        switch result {
        case .perfect:
            flash(.hitPerfect, at: key, now: now)
            if playSound { cue?.playHit() }
        case .good:
            flash(.hitGood, at: key, now: now)
            if playSound { cue?.playHit() }
        case .lateEarly:
            flash(.wrongOrOffBeat, at: key, now: now)
            if playSound { cue?.playHit() }
        case .wrongKey:
            flash(.wrongOrOffBeat, at: key, now: now)
            if playSound { cue?.playMiss() }
        case .miss:
            // Auto-miss on timeout: DO NOT flash fill on key rect!
            // Fills ONLY happen when the user physically strikes a key!
            if playSound { cue?.playMiss() }
        }
    }

    private func flash(_ kind: FlashKind, at key: Int, now: Double) {
        flashes[key] = (kind, now + flashDuration)
    }

    private func rebuildApproachTrack() {
        guard mode == .play else { approachNotes = []; return }
        let lookahead = Theme.approachLookaheadSeconds
        var out: [ApproachNote] = []
        for i in notes.indices where !judged[i] {
            let untilSec = (scaledTime(notes[i]) - currentTimeMs) / 1000
            guard untilSec <= lookahead, untilSec >= -0.2 else { continue }
            let strike = Theme.strikeLineFraction
            let x = strike + (untilSec / lookahead) * (1 - strike)
            out.append(ApproachNote(id: notes[i].id, keyIndex: notes[i].keyIndex, xFraction: min(1, max(0, x))))
        }
        approachNotes = out
    }

    private func checkCompletion(now: Double) {
        switch mode {
        case .play:
            let tail = Double(song.durationMs) / tempoScale + 500
            if currentTimeMs > tail, judged.allSatisfy({ $0 }) {
                finish()
            }
        case .practice:
            if practiceIndex >= notes.count {
                finish()
            }
        }
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        cue?.stop()
        if mode == .play {
            onComplete?(SongResult(songTitle: song.title, subtitle: sessionSubtitle, judgements: results))
        } else {
            onComplete?(nil) // practice: no score
        }
    }
}

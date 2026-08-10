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

enum FlashKind: Equatable { case hit, miss, wrong }

enum SessionPhase: Equatable {
    case countIn    // gong only
    case example    // app plays + shows
    case userTurn   // user plays, highlight only
    
    var isUserPlaying: Bool { self == .userTurn }
}

/// What the overlay should draw for a single key this frame.
struct KeyRenderState: Equatable {
    var fill: Double = 0        // upcoming fill, 0…1 (§13.5 "fills from bottom")
    var strikeNow: Bool = false // solid highlight pulse
    var flash: FlashKind? = nil // transient hit/miss/wrong
    var damp: Bool = false      // dashed damp hint on the previous key (§5.5)
    var approachScale: Double = 0
}

/// A note approaching on the bottom track (§13.5).
struct ApproachNote: Identifiable, Equatable {
    let id: String
    let keyIndex: Int
    let xFraction: Double       // 0…1 across the track; strike line at 0.15
}

struct TrackMarker: Identifiable, Equatable {
    enum Kind: Equatable { case gong, kempur, kemong, beat }
    let id: Int
    let kind: Kind
    let xFraction: Double
}

@Observable
final class PlayEngine {
    
    // Rendering outputs
    private(set) var renderStates: [Int: KeyRenderState] = [:]
    private(set) var approachNotes: [ApproachNote] = []
    private(set) var trackMarkers: [TrackMarker] = []
    private(set) var currentTimeMs: Double = 0
    private(set) var currentBeatIndex: Int = 0
    private(set) var isFinished = false
    private(set) var phase: SessionPhase = .countIn
    private(set) var loopIndex: Int = 0
    
    // Live judgement feed (for debug / practice feedback)
    private(set) var lastJudgement: NoteJudgement?
    
    // Dependencies set before start
    var cue: CuePlayer?
    var metronomeEnabled = true
    var referenceToneEnabled = true
    var onComplete: ((SongResult?) -> Void)?
    
    // Config
    private var song: Song = ResourceLoader.bundledSongs().first ?? Song(id: "", title: "", difficulty: .beginner, bpm: 60, requiredKeys: 0, durationMs: 0, notes: [])
    private var profile: InstrumentProfile?
    private var mode: PlayMode = .play
    private var tempoScale: Double = 1
    
    // Play-mode state
    private var notes: [Note] = []
    private var judged: [Bool] = []
    private var results: [JudgementResult] = []
    
    private var referencedNotes: Set<String> = []
    private var lastBeatIndex = -1
    
    
    // Practice-mode state
    private var practiceIndex = 0
    
    // Transient flash bookkeeping: keyIndex -> (kind, expiry host time)
    private var flashes: [Int: (FlashKind, Double)] = [:]
    
    private var startHostTime: Double = 0
    
    // Tunables
    private let approachWindowMs: Double = 2200          // upcoming fill lead-in
    private let missWindowMs: Double = 200               // §5.1
    private let flashDuration: Double = 0.3
    
    // One full colotomic cycle of gong before anything else happens.
    private let introBeats = 8
    // Silent beats between loops so a repeat doesn't feel clipped.
    private let loopGapBeats = 2
    
    private var introMs: Double = 0
    private var patternMs: Double = 0
    private var patternOriginMs: Double = 0
    private var lastLoopIndex = -1// 300ms fades (§13.5)
    
    // MARK: - Lifecycle
    
    func configure(song: Song, mode: PlayMode, profile: InstrumentProfile, tempoScale: Double) {
        self.song = song
        self.mode = mode
        self.profile = profile
        self.tempoScale = (mode == .practice) ? max(0.25, tempoScale) : 1
        self.notes = song.notes.sorted { $0.timeMs < $1.timeMs }
        self.judged = Array(repeating: false, count: notes.count)
        self.results = []
        self.referencedNotes = []
        self.practiceIndex = 0
        self.lastBeatIndex = -1
        self.flashes = [:]
        self.isFinished = false
        self.renderStates = [:]
        self.lastLoopIndex = -1
        self.phase = .countIn
        self.loopIndex = 0
        recomputeTiming()
    }
    
    func start() {
        startHostTime = CACurrentMediaTime()
        cue?.start()
    }
    
    /// Shift the clock forward to absorb a pause (§13.4 .paused).
    func adjustStart(by seconds: Double) {
        startHostTime += seconds
    }
    
    func setTempoScale(_ scale: Double) {
        guard mode != .play else { return }
        tempoScale = max(0.25, scale)
        recomputeTiming()
    }
    
    private func recomputeTiming() {
        let beatMs = 60000.0 / Double(song.bpm) / tempoScale
        introMs = Double(introBeats) * beatMs
        let lastEnd = notes.map { Double($0.timeMs + $0.durationMs) }.max() ?? 0
        patternMs = lastEnd / tempoScale + Double(loopGapBeats) * beatMs
        if patternMs <= 0 { patternMs = beatMs * 4 }
    }
    
    private func scaledTime(_ note: Note) -> Double { Double(note.timeMs) / tempoScale }
    
    // MARK: - Frame tick
    
    func tick(now: Double) {
        guard !isFinished else { return }
        currentTimeMs = (now - startHostTime) * 1000
        
        let beatMs = 60000.0 / Double(song.bpm) / tempoScale
        
        //phase and loop bookkeeping
        if currentTimeMs < introMs {
            phase = .countIn
            loopIndex = 0
            patternOriginMs = introMs
        } else {
            let sinceIntro = currentTimeMs - introMs
            let idx = Int((sinceIntro / patternMs).rounded(.down))
            loopIndex = idx
            patternOriginMs = introMs + Double(idx) * patternMs
            phase = (idx == 0) ? .example : .userTurn
            
            if idx != lastLoopIndex {
                lastLoopIndex = idx
                judged = Array(repeating: false, count: notes.count)
                flashes = [:]
                if mode == .practice { practiceIndex = 0 }
            }
        }
        
        var states: [Int: KeyRenderState] = [:]
        
        for (key, entry) in flashes where now <= entry.1 {
            var s = states[key] ?? KeyRenderState()
            s.flash = entry.0
            states[key] = s
        }
        flashes = flashes.filter { now <= $0.value.1 }
        
        let beatIndex = Int(currentTimeMs / beatMs)
        currentBeatIndex = max(0, beatIndex)
        if beatIndex != lastBeatIndex, currentTimeMs >= 0 {
            lastBeatIndex = beatIndex
            switch beatIndex % 8 {
            case 0:
                cue?.playGong()

            case 2, 6:
                cue?.playKemong()

            case 4:
                cue?.playKempur()

            default:
                cue?.playClick()
            }
            if metronomeEnabled { cue?.playClick() }
        }
        
        let patternTime = currentTimeMs - patternOriginMs
        
        switch phase {
        case .countIn:
            break
        case .example:
            tickExample(now: now, patternTime: patternTime, states: &states)
        case .userTurn:
            if mode == .practice {
                tickPractice(patternTime: patternTime, states: &states)
            } else {
                tickPlay(now: now, patternTime: patternTime, states: &states)
            }
        }
        
        renderStates = states
        rebuildTrack(beatMs: beatMs)
        checkCompletion(now: now)
    }
    
    //BATAS SUCI
    //        func ensure(_ i: Int) -> KeyRenderState { states[i] ?? KeyRenderState() }
    //
    //        // Carry over live flashes.
    //        for (key, entry) in flashes {
    //            if now <= entry.1 {
    //                var s = ensure(key); s.flash = entry.0; states[key] = s
    //            }
    //        }
    //        flashes = flashes.filter { now <= $0.value.1 }
    //
    //        switch mode {
    //        case .play:
    //            tickPlay(now: now, states: &states)
    //        case .practice:
    //            tickPractice(now: now, states: &states)
    //        }
    //
    //        renderStates = states
    //        rebuildApproachTrack()
    //        checkCompletion(now: now)
    //    }
    
    // The app demonstrates: highlight the bilah AND play its recorded sample.
    private func tickExample(now: Double, patternTime: Double, states: inout [Int: KeyRenderState]) {
        for i in notes.indices where !judged[i] {
            let until = scaledTime(notes[i]) - patternTime
            let key = notes[i].keyIndex
            
            if until <= approachWindowMs && until >= -missWindowMs {
                applyCue(&states, key: key, until: until)
            }
            if until <= 0, until > -40 {
                judged[i] = true

                cue?.playKeySample(index: key)

                flash(.hit, at: key, now: now)
            }
        }
    }
    
    private func tickPlay(now: Double, patternTime: Double, states: inout [Int: KeyRenderState]) {
        // Auto-miss notes whose window has fully passed.
        for i in notes.indices where !judged[i] {
            if patternTime > scaledTime(notes[i]) + missWindowMs {
                judged[i] = true
                record(.miss, at: notes[i].keyIndex, now: now, playSound: true)
            }
        }
        // Upcoming fills + strike-now, plus reference-tone one beat ahead.
        //        let beatMs = 60000.0 / Double(song.bpm) / tempoScale
        for i in notes.indices where !judged[i] {
            let until = scaledTime(notes[i]) - patternTime
            if until <= approachWindowMs && until >= -missWindowMs {
                applyCue(&states, key: notes[i].keyIndex, until: until)
            }
        }
        //
        //        /** BATAS*/
        //        // Metronome on the beat (§5.4).
        //        if metronomeEnabled {
        //            let beatIndex = Int(currentTimeMs / beatMs)
        //            if beatIndex != lastBeatIndex, currentTimeMs >= 0 {
        //                lastBeatIndex = beatIndex
        //                cue?.playClick()
        //            }
        //        }
    }
    
    private func tickPractice(patternTime: Double, states: inout [Int: KeyRenderState]) {
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
    
    private func applyCue(_ states: inout [Int: KeyRenderState], key: Int, until: Double) {
        var s = states[key] ?? KeyRenderState()
        let fill = 1 - max(0, until) / approachWindowMs
        s.fill = max(s.fill, min(1, fill))
        let scale = 1.6 - 0.6 * min(1, max(0, fill))
        s.approachScale = s.approachScale > 0 ? min(s.approachScale, scale) : scale
        if abs(until) <= 60 { s.strikeNow = true }
        states[key] = s
    }
    
    // MARK: - Strike handling (from AudioEngineController, main queue)
    
    func registerStrike(keyIndex: Int, hostTime: Double, confidence: Double) {
        guard !isFinished, phase.isUserPlaying else { return }
        switch mode {
        case .play: registerPlayStrike(keyIndex: keyIndex, hostTime: hostTime)
        case .practice: registerPracticeStrike(keyIndex: keyIndex, hostTime: hostTime)
        }
    }
    
    private func registerPlayStrike(keyIndex: Int, hostTime: Double) {
        let atMs = (hostTime - startHostTime) * 1000 - patternOriginMs
        // Nearest unjudged note in time within the miss window.
        var target: Int?
        var bestErr = missWindowMs
        for i in notes.indices where !judged[i] {
            let err = abs(scaledTime(notes[i]) - atMs)
            if err <= bestErr { bestErr = err; target = i }
        }
        guard let i = target else { return } // stray strike, ignore
        
        judged[i] = true
        if notes[i].keyIndex == keyIndex {
            record(JudgementResult.from(timingErrorMs: scaledTime(notes[i]) - atMs), at: keyIndex, now: hostTime, playSound: true)
        } else {
            // Correct timing, wrong key: amber on struck key, correct stays lit.
            record(.wrongKey, at: keyIndex, now: hostTime, playSound: true, storeResult: true)
        }
    }
    
    private func registerPracticeStrike(keyIndex: Int, hostTime: Double) {
        guard practiceIndex < notes.count else { return }
        if keyIndex == notes[practiceIndex].keyIndex {
            flash(.hit, at: keyIndex, now: hostTime)
            cue?.playHit()
            practiceIndex += 1
        } else {
//            flash(.wrong, at: keyIndex, now: hostTime)
        }
    }
    
    // MARK: - Bottom track
    
    /// Builds one row: colotomic markers (gong/kempur/kemong/beat) and the note
    /// numbers, both mapped from the same absolute clock so they stay aligned.
    private func rebuildTrack(beatMs: Double) {
        let lookahead = Theme.approachLookaheadSeconds
        let strike = Theme.strikeLineFraction
        
        func xFor(_ absMs: Double) -> Double? {
            let untilSec = (absMs - currentTimeMs) / 1000
            guard untilSec <= lookahead, untilSec >= -0.25 else { return nil }
            return min(1, max(0, strike + (untilSec / lookahead) * (1 - strike)))
        }
        
        var marks: [TrackMarker] = []
        let firstBeat = max(0, Int((currentTimeMs - 400) / beatMs))
        let lastBeat = Int((currentTimeMs + lookahead * 1000) / beatMs) + 1
        if lastBeat >= firstBeat {
            for b in firstBeat...lastBeat {
                guard let x = xFor(Double(b) * beatMs) else { continue }
                let kind: TrackMarker.Kind
                switch b % 8 {
                case 0: kind = .gong
                case 4: kind = .kempur
                case 2, 6: kind = .kemong
                default: kind = .beat
                }
                marks.append(TrackMarker(id: b, kind: kind, xFraction: x))
            }
        }
        trackMarkers = marks
        
        // Notes are only cued once the example starts.
        guard phase != .countIn else { approachNotes = []; return }
        var out: [ApproachNote] = []
        for i in notes.indices where !judged[i] {
            guard let x = xFor(patternOriginMs + scaledTime(notes[i])) else { continue }
            out.append(ApproachNote(id: notes[i].id, keyIndex: notes[i].keyIndex, xFraction: x))
        }
        // Next loop's notes, so the row never looks empty near the boundary.
        for i in notes.indices {
            guard let x = xFor(patternOriginMs + patternMs + scaledTime(notes[i])) else { continue }
            out.append(ApproachNote(id: notes[i].id + "+1", keyIndex: notes[i].keyIndex, xFraction: x))
        }
        approachNotes = out
    }
    
    // MARK: - Helpers
    
    private func record(_ result: JudgementResult, at key: Int, now: Double, playSound: Bool, storeResult: Bool = true) {
        if storeResult { results.append(result) }
        lastJudgement = NoteJudgement(noteIndex: key, result: result, timingErrorMs: 0)
        switch result {
        case .perfect, .good, .lateEarly:
            flash(.hit, at: key, now: now)
            if playSound { cue?.playHit() }
        case .miss:
            flash(.miss, at: key, now: now)
            if playSound { cue?.playMiss() }
        case .wrongKey:
            flash(.wrong, at: key, now: now)
            if playSound { cue?.playMiss() }
        }
    }
    
    private func flash(_ kind: FlashKind, at key: Int, now: Double) {
        flashes[key] = (kind, now + flashDuration)
    }
    
    //    private func rebuildApproachTrack() {
    //        guard mode == .play else { approachNotes = []; return }
    //        let lookahead = Theme.approachLookaheadSeconds
    //        var out: [ApproachNote] = []
    //        for i in notes.indices where !judged[i] {
    //            let untilSec = (scaledTime(notes[i]) - currentTimeMs) / 1000
    //            guard untilSec <= lookahead, untilSec >= -0.2 else { continue }
    //            let strike = Theme.strikeLineFraction
    //            let x = strike + (untilSec / lookahead) * (1 - strike)
    //            out.append(ApproachNote(id: notes[i].id, keyIndex: notes[i].keyIndex, xFraction: min(1, max(0, x))))
    //        }
    //        approachNotes = out
    //    }
    
    private func checkCompletion(now: Double) {
        switch mode {
        case .play:
            //            let tail = Double(song.durationMs) / tempoScale + 500
            if loopIndex >= 2 { finish() }
        case .practice:
            break
        }
    }
    
    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        cue?.stop()
        //        if mode == .play {
        //            onComplete?(SongResult(songTitle: song.title, judgements: results))
        //        } else {
        onComplete?(mode == .play ? SongResult(songTitle: song.title, judgements: results) : nil) // practice: no score
    }
}

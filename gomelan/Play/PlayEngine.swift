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

enum SessionPhase: Equatable {
    case countIn    // gong only
    case example    // app plays + shows
    case userTurn   // user plays, highlight only

    var isUserPlaying: Bool { self == .userTurn }
}

/// Which half of the session this engine is running (§4 Flow C).
///
/// Demo and practice are separate screens: the demo loops the figure for as
/// long as the player wants to watch and listen, and the practice run hands the
/// instrument over straight after the count-in. One engine, two roles, so the
/// timing, cues and overlay are identical in both.
enum SessionRole: Equatable {
    case demo
    case practice
}

/// What the overlay should draw for a single key this frame.
struct KeyRenderState: Equatable {
    var fill: Double = 0        // upcoming fill, 0…1 (§13.5 "fills from bottom")
    var strikeNow: Bool = false // solid highlight pulse
    var flash: FlashKind? = nil // transient hit/miss/wrong
    var damp: Bool = false      // dashed damp hint on the previous key (§5.5)
    var approachScale: Double = 0
}

/// Which of the two interlocking halves a note belongs to.
enum NoteVoice: Equatable {
    case yours      // the half you are learning
    case partner    // the half the app plays beside you
}

/// A note travelling along the river (§13.5). Position is time (x) against
/// pitch (the key index), so the two halves read as one woven line.
struct ApproachNote: Identifiable, Equatable {
    let id: String
    let keyIndex: Int
    let voice: NoteVoice
    let xFraction: Double       // 0…1 across the track; strike line at 0.15
    /// How wide the stroke is in track units — the note's own duration.
    let widthFraction: Double
    /// Set once your note has been judged, so its trail shows how it went.
    var outcome: JudgementResult? = nil
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
    private(set) var role: SessionRole = .practice
    /// Fractional index into `notes` at the current pattern time: `2.5` is
    /// halfway between the third and fourth stroke. Interpolated from the real
    /// note times, so it stays honest on figures whose strokes are unevenly
    /// spaced. Negative during the count-in, before the figure has started.
    private(set) var noteProgress: Double = 0
    
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
    /// How each of your notes turned out this loop — colours its trail on the
    /// river. Separate from `judged`, which the example also uses as a "fired".
    private var outcomes: [JudgementResult?] = []
    private var results: [NoteJudgement] = []
    private var referencedNotes: Set<String> = []
    private var lastBeatIndex = -1
    
    
    // The partner's half: sounded by the app, never judged (§7).
    private var partnerNotes: [Note] = []
    private var partnerFired: [Bool] = []
    /// The three voices, independently mutable. Learning a half often means
    /// silencing everything else first and putting it back once the figure is in
    /// the hands — so each is a switch, not a fixed arrangement.
    var partnerAudible = true
    var yourVoiceAudible = true
    var colotomicAudible = true
    /// Stereo placement of the two halves, so they read as two players.
    private let yourPan: Float = -0.32
    private let partnerPan: Float = 0.32

    // Practice-mode state
    private(set) var practiceIndex = 0
    // Transient flash bookkeeping: keyIndex -> (kind, expiry host time)
    private var flashes: [Int: (FlashKind, Double)] = [:]
    
    private var startHostTime: Double = 0
    
    // Tunables
    private let approachWindowMs: Double = 2200          // upcoming fill lead-in
    private let missWindowMs: Double = 200               // §5.1
    private let practiceWindowMs: Double = 350           //R generous, practice is no-fail
    private let flashDuration: Double = 0.3
    
    // One full colotomic cycle of gong before anything else happens.
    private let introBeats = 8
    /// Silent beats between loops so a repeat doesn't feel clipped. The demo
    /// repeats the same figure over and over, so it closes the gap and lets the
    /// gong land exactly on the turn of the cycle.
    private var loopGapBeats: Int { role == .demo ? 0 : 2 }
    
    private var introMs: Double = 0
    private var patternMs: Double = 0
    private var patternOriginMs: Double = 0
    private var lastLoopIndex = -1// 300ms fades (§13.5)
    
    // MARK: - Lifecycle
    
    func configure(song: Song, partner: Song? = nil, mode: PlayMode, profile: InstrumentProfile,
                   tempoScale: Double, role: SessionRole = .practice) {
        self.role = role
        self.song = song
        self.mode = mode
        self.profile = profile
        // A scored run is always at tempo; the demo and no-fail practice can slow down.
        self.tempoScale = (role == .demo || mode == .practice) ? max(0.25, tempoScale) : 1
        self.notes = song.notes.sorted { $0.timeMs < $1.timeMs }
        self.judged = Array(repeating: false, count: notes.count)
        self.outcomes = Array(repeating: nil, count: notes.count)
        self.partnerNotes = (partner?.notes ?? []).sorted { $0.timeMs < $1.timeMs }
        self.partnerFired = Array(repeating: false, count: partnerNotes.count)
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
        self.noteProgress = 0
        self.currentTimeMs = 0
        recomputeTiming()
    }
    
    func start() {
        //R Booting the audio engine loads and decodes 13 samples, which took
        //R long enough that the clock had already run on without the cues.
        //R Start the cue player first, then stamp the clock.
        cue?.start()
        startHostTime = CACurrentMediaTime()
    }
    
    /// Shift the clock forward to absorb a pause (§13.4 .paused).
    func adjustStart(by seconds: Double) {
        startHostTime += seconds
    }
    
    func setTempoScale(_ scale: Double) {
        guard role == .demo || mode != .play else { return }
        tempoScale = max(0.25, scale)
        recomputeTiming()
    }

    private func recomputeTiming() {
        let beatMs = 60000.0 / Double(song.bpm) / tempoScale
        introMs = Double(introBeats) * beatMs
        //R The loop has to be the figure's MUSICAL length (whole gong cycles),
        //R not the end of its last note — the last slots of a kotekan are often
        //R rests, and cutting them made every repeat land early and rush.
        let lastEnd = notes.map { Double($0.timeMs + $0.durationMs) }.max() ?? 0
        patternMs = max(Double(song.durationMs), lastEnd) / tempoScale + Double(loopGapBeats) * beatMs
        if patternMs <= 0 { patternMs = beatMs * 4 }
    }
    
    private func scaledTime(_ note: Note) -> Double { Double(note.timeMs) / tempoScale }
    
    // MARK: - Frame tick
    
    func tick(now: Double) {
        guard !isFinished else { return }
        currentTimeMs = (now - startHostTime) * 1000
        
        let beatMs = 60000.0 / Double(song.bpm) / tempoScale
        
        let previousPhase = phase   //R

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
            //R The demo and the hand-over used to be two loops of one session,
            //R which meant sitting through the whole figure before playing a
            //R note. They are separate screens now, so the role decides.
            phase = (role == .demo) ? .example : .userTurn

            if idx != lastLoopIndex {
                lastLoopIndex = idx
                judged = Array(repeating: false, count: notes.count)
                outcomes = Array(repeating: nil, count: notes.count)
                partnerFired = Array(repeating: false, count: partnerNotes.count)
                flashes = [:]
                if mode == .practice { practiceIndex = 0 }
            }
        }

        //R The gangsa samples belong to the example. Cut whatever is still
        //R ringing the moment "Your turn" starts, so the player isn't listening
        //R to the app while they're supposed to be playing.
        if phase != previousPhase, previousPhase == .example {
            cue?.stopKeySamples()
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
            if colotomicAudible {
                switch beatIndex % 8 {
                case 0:
                    cue?.playGong()

                case 2, 6:
                    cue?.playKemong()

                case 4:
                    cue?.playKempur()

                default:
                    break   //R off-beats got a click here AND from the metronome below
                }
            }
            if metronomeEnabled { cue?.playClick() }
        }
        
        let patternTime = currentTimeMs - patternOriginMs
        
        //R Your partner sounds under both phases: in the demo you hear the two
        //R halves woven together, and in your turn the other half keeps going
        //R around you, which is the whole point of kotekan.
        if phase != .countIn { tickPartner(patternTime: patternTime) }

        switch phase {
        case .countIn:
            break
        case .example:
            tickExample(now: now, patternTime: patternTime, states: &states)
        case .userTurn:
            //R The bilah cue in "Your turn" is now driven purely by the clock, so
            //R it always names the same key as the number sitting on the strike
            //R line below. Play judges first, so a note it retires this frame
            //R doesn't get cued.
            if mode == .practice {
                tickUserTurnCue(patternTime: patternTime, beatMs: beatMs, states: &states)
                tickPractice(patternTime: patternTime, states: &states)
            } else {
                tickPlay(now: now, patternTime: patternTime, states: &states)
                tickUserTurnCue(patternTime: patternTime, beatMs: beatMs, states: &states)
            }
        }
        
        renderStates = states
        noteProgress = noteProgress(patternTime: patternTime)
        rebuildTrack(beatMs: beatMs)
        checkCompletion(now: now)
    }

    /// Where the playhead sits in note-index space: `2.5` means halfway between
    /// the third and fourth note. Interpolating between the real note times is
    /// what keeps the scrolling row honest on figures whose strokes are unevenly
    /// spaced (a rest between two notes is twice the gap of two adjacent ones).
    private func noteProgress(patternTime: Double) -> Double {
        guard let first = notes.first else { return 0 }
        guard notes.count > 1 else {
            return patternTime >= scaledTime(first) ? 0 : -1
        }
        let firstGap = scaledTime(notes[1]) - scaledTime(first)
        if patternTime <= scaledTime(first) {
            return (patternTime - scaledTime(first)) / max(1, firstGap)
        }
        for i in 0..<(notes.count - 1) {
            let start = scaledTime(notes[i])
            let end = scaledTime(notes[i + 1])
            if patternTime < end {
                return Double(i) + (patternTime - start) / max(1, end - start)
            }
        }
        let last = notes.count - 1
        let lastGap = scaledTime(notes[last]) - scaledTime(notes[last - 1])
        return Double(last) + (patternTime - scaledTime(notes[last])) / max(1, lastGap)
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
    
    //R The bilah cue itself: fill + approach ring for every note inside the
    //R lead-in window. Shared by the example and by "Your turn" (both modes) so
    //R the guidance is identical and unbroken across the phase change.
    private func applyTimedCues(patternTime: Double, states: inout [Int: KeyRenderState]) {
        for i in notes.indices where !judged[i] {
            let until = scaledTime(notes[i]) - patternTime
            if until <= approachWindowMs && until >= -missWindowMs {
                applyCue(&states, key: notes[i].keyIndex, until: until)
            }
        }
    }

    //R --------------------------------------------------------------------
    //R "Your turn" cue.
    //R
    //R The bottom row and the bilah are both mapped from the same clock, so the
    //R rule is simply: whichever number is on the strike line, that bilah is lit.
    //R The note that has just arrived holds a solid highlight, then releases in
    //R time for the next note's fill to read (otherwise a 4→4 repeat looks like
    //R one long highlight). Nothing here waits on onset detection — that hold was
    //R what pinned the highlight to one bilah while the row scrolled on.
    //R --------------------------------------------------------------------

    /// The note the row is showing at the strike line: the latest one whose time
    /// has arrived. `notes` is sorted, so scan forward and keep the last match.
    private func currentNoteIndex(patternTime: Double) -> Int? {
        var current: Int?
        for i in notes.indices {
            guard scaledTime(notes[i]) <= patternTime else { break }
            current = i
        }
        if let current, judged[current] { return nil }   // already hit or missed
        return current
    }

    /// The next note still to come — the one the fill counts down to.
    private func nextNoteIndex(patternTime: Double) -> Int? {
        notes.indices.first { scaledTime(notes[$0]) > patternTime && !judged[$0] }
    }

    private func tickUserTurnCue(patternTime: Double, beatMs: Double, states: inout [Int: KeyRenderState]) {
        // Lead-in on the next note. It fills across the gap since the previous
        // note, so the countdown matches the spacing of the numbers on the row
        // instead of washing every key at once with a fixed 2.2s window.
        if let next = nextNoteIndex(patternTime: patternTime) {
            let dueAt = scaledTime(notes[next])
            let previous = next > 0 ? scaledTime(notes[next - 1]) : dueAt - beatMs
            let window = max(120, dueAt - previous)
            let until = dueAt - patternTime
            if until <= window {
                let fill = min(1, max(0, 1 - until / window))
                var s = states[notes[next].keyIndex] ?? KeyRenderState()
                s.fill = max(s.fill, fill)
                s.approachScale = 1.6 - 0.6 * fill
                states[notes[next].keyIndex] = s
            }
        }

        // Solid highlight on the note that is due right now.
        if let current = currentNoteIndex(patternTime: patternTime) {
            let dueAt = scaledTime(notes[current])
            let gap = current + 1 < notes.count ? scaledTime(notes[current + 1]) - dueAt : beatMs
            let hold = min(max(gap * 0.55, 90), 400)
            if patternTime < dueAt + hold {
                var s = states[notes[current].keyIndex] ?? KeyRenderState()
                s.strikeNow = true
                s.fill = 1
                states[notes[current].keyIndex] = s
            }
        }
    }

    /// The partner's half — sounded, never judged and never cued on the bilah:
    /// those keys are not yours to strike.
    private func tickPartner(patternTime: Double) {
        guard partnerAudible, !partnerNotes.isEmpty else { return }
        for i in partnerNotes.indices where !partnerFired[i] {
            let until = scaledTime(partnerNotes[i]) - patternTime
            if until <= 0, until > -60 {
                partnerFired[i] = true
                cue?.playKeySample(index: partnerNotes[i].keyIndex, pan: partnerPan, volume: 0.85)
            }
        }
    }

    // The app demonstrates: highlight the bilah AND play its recorded sample.
    private func tickExample(now: Double, patternTime: Double, states: inout [Int: KeyRenderState]) {
        applyTimedCues(patternTime: patternTime, states: &states)   //R
        for i in notes.indices where !judged[i] {
            let until = scaledTime(notes[i]) - patternTime
            let key = notes[i].keyIndex

            if until <= 0, until > -40 {
                judged[i] = true

                // Muting your own half still SHOWS it on the bilah — you can
                // watch the figure without hearing it played for you.
                if yourVoiceAudible { cue?.playKeySample(index: key, pan: yourPan) }

                flash(.hit, at: key, now: now)
            }
        }
    }

    private func tickPlay(now: Double, patternTime: Double, states: inout [Int: KeyRenderState]) {
        // Auto-miss notes whose window has fully passed.
        for i in notes.indices where !judged[i] {
            if patternTime > scaledTime(notes[i]) + missWindowMs {
                judged[i] = true
                outcomes[i] = .miss
                record(.miss, at: notes[i].keyIndex, now: now, playSound: true)
            }
        }
        // Upcoming fills + strike-now, plus reference-tone one beat ahead.
        //        let beatMs = 60000.0 / Double(song.bpm) / tempoScale
        //R The fills now come from tickUserTurnCue, which is locked to the row.
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
        //R The expected-key hold lived here; it froze on one bilah until onset
        //R detection fired, which is what looked like lag. The highlight comes
        //R from tickUserTurnCue now, so all practice adds is the damp hint.
        guard let current = currentNoteIndex(patternTime: patternTime), current > 0 else { return }

        // Damp hint on the previous key (§5.5) — teach it, don't score it.
        let prev = notes[current - 1].keyIndex
        guard prev != notes[current].keyIndex else { return }
        var ps = states[prev] ?? KeyRenderState()
        ps.damp = true
        states[prev] = ps
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
        let err = scaledTime(notes[i]) - atMs
        if notes[i].keyIndex == keyIndex {
            let result = JudgementResult.from(timingErrorMs: err)
            outcomes[i] = result
            record(result, at: keyIndex, now: hostTime, playSound: true, timingErrorMs: err)
        } else {
            // Correct timing, wrong key: amber on struck key, correct stays lit.
            outcomes[i] = .wrongKey
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
    
    // MARK: - The river (§13.5)

    /// Builds one frame of the river: the colotomic pulse (gong/kempur/kemong/
    /// beat) and both halves' notes, all mapped from the same absolute clock so
    /// the weave stays aligned. Time runs along x, pitch is the key index, and
    /// the strike line sits at `Theme.strikeLineFraction`.
    private func rebuildTrack(beatMs: Double) {
        let lookahead = Theme.approachLookaheadSeconds
        let strike = Theme.strikeLineFraction
        let trail = Theme.approachTrailSeconds

        func xFor(_ absMs: Double) -> Double? {
            let untilSec = (absMs - currentTimeMs) / 1000
            guard untilSec <= lookahead, untilSec >= -trail else { return nil }
            //R Not clamped any more: a played stroke has to keep sliding left
            //R off the edge, otherwise everything piles up on x = 0.
            return strike + (untilSec / lookahead) * (1 - strike)
        }

        /// A note's own length, in the same units as `xFraction`.
        func widthFor(_ note: Note) -> Double {
            let seconds = Double(note.durationMs) / tempoScale / 1000
            return (seconds / lookahead) * (1 - strike)
        }

        var marks: [TrackMarker] = []
        let firstBeat = max(0, Int((currentTimeMs - trail * 1000) / beatMs))
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

        // Notes are only shown once the count-in is over.
        guard phase != .countIn else { approachNotes = []; return }
        var out: [ApproachNote] = []

        //R Three loops' worth of origins: the one just gone (its last strokes are
        //R still sliding away to the left), the current one, and the next (so the
        //R river never runs dry at the turn of the cycle).
        for loop in -1...1 {
            let origin = patternOriginMs + Double(loop) * patternMs
            let suffix = loop == 0 ? "" : "\(loop)"

            for i in notes.indices {
                guard let x = xFor(origin + scaledTime(notes[i])) else { continue }
                out.append(ApproachNote(id: "y\(suffix)-\(notes[i].id)",
                                        keyIndex: notes[i].keyIndex,
                                        voice: .yours,
                                        xFraction: x,
                                        widthFraction: widthFor(notes[i]),
                                        outcome: loop == 0 ? outcomes[i] : nil))
            }

            for i in partnerNotes.indices {
                guard let x = xFor(origin + scaledTime(partnerNotes[i])) else { continue }
                out.append(ApproachNote(id: "p\(suffix)-\(partnerNotes[i].id)",
                                        keyIndex: partnerNotes[i].keyIndex,
                                        voice: .partner,
                                        xFraction: x,
                                        widthFraction: widthFor(partnerNotes[i])))
            }
        }
        approachNotes = out
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
        //R The demo loops until the player says they're ready; only the scored
        //R run ends by itself, and now after ONE pass — the example pass it used
        //R to sit through lives on its own screen.
        guard role == .practice, mode == .play else { return }
        if loopIndex >= 1 { finish() }
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

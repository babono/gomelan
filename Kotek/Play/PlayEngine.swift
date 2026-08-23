//
//  PlayEngine.swift
//  Kotek
//
//  The core loop (PRD §4 Flow C, §5.1). Timing, judgement, overlay state and cue
//  triggering. Driven by tick(now:) from a TimelineView(.animation) so timing is
//  frame-accurate (§13.5).
//
//  ONE session, looping until the player stops it. This used to be four things:
//  a demo role that played the figure at you, a scored mode that ran N cycles
//  and ended, a no-fail practice mode that waited for the right key, and a
//  screen apiece to configure them. A gangsa player's verdict on that flow was
//  that it is too much to get through before you can play a note — so the
//  figure now simply goes around, scoring quietly in the background, and the
//  only decision left inside a session is which half you are taking.
//
//  Nothing here fails or ends on its own. `end()` is called by the screen.
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
    case countIn    // gong only, one colotomic cycle
    case userTurn   // the figure is going round; you play

    var isUserPlaying: Bool { self == .userTurn }
}

/// What the overlay should draw for a single key this frame.
struct KeyRenderState: Equatable {
    var fill: Double = 0        // the NEAREST stroke's progress, 0…1 — the bar that fills from the bottom
    var strikeNow: Bool = false // solid highlight pulse
    var flash: FlashKind? = nil // transient hit/miss/wrong
    var damp: Bool = false      // dashed damp hint on the previous key (§5.5)
    /// Every upcoming stroke on this bilah that is inside the cue window,
    /// nearest first — one ring each, nested.
    ///
    /// A list rather than a single value because kotekan repeat a bar: on
    /// Ubitan Nyendok key 7 is struck three times in eight slots, so inside a
    /// four-beat window that bilah usually has TWO strokes coming. Collapsing
    /// them to the nearest threw away the more useful half of the information —
    /// "this bar, then this bar again" is the thing a player needs to see
    /// coming, and it is exactly what a single ring cannot say.
    var approaches: [Double] = []
}

/// Which of the two interlocking halves a note belongs to.
enum NoteVoice: Equatable {
    case yours      // the half you are learning
    case partner    // the half the app plays beside you
}

/// One stroke of the figure, placed on the CYCLE rather than on a moving
/// stream (§13.5). `x` is where in the pattern it falls, 0…1, and it never
/// moves — the playhead does.
///
/// The river used to scroll: notes slid right to left across a strike line, and
/// three loops' worth of them had to be rendered at once so the stream never
/// ran dry at the turn. It read as a rhythm game rather than as a figure. A
/// kotekan is a fixed, memorisable shape that repeats, and showing it as one
/// still shape you sweep through is both closer to what it is and far easier to
/// learn from — the pattern stays put long enough to be read.
struct CycleNote: Identifiable, Equatable {
    let id: String
    let keyIndex: Int
    let voice: NoteVoice
    let x: Double               // 0…1 through the pattern
    let width: Double           // the stroke's own duration, same units
    /// Set once your note has been judged this pass; cleared at the turn.
    var outcome: JudgementResult? = nil
    /// The stroke due right now — what the bilah overlay is lighting.
    var isCurrent: Bool = false
}

struct TrackMarker: Identifiable, Equatable {
    enum Kind: Equatable { case gong, kempur, kajar, beat }
    let id: Int
    let kind: Kind
    let xFraction: Double
}

/// One completed pass, accumulated while it runs.
private struct CycleTally {
    var startMs: Double = 0
    var noteCount = 0
    var score = 0
    var onBeat = 0
    var mistakes = 0
}

@Observable
final class PlayEngine {
    
    // Rendering outputs
    private(set) var renderStates: [Int: KeyRenderState] = [:]
    /// The figure laid out across one pattern, still.
    private(set) var cycleNotes: [CycleNote] = []
    /// Where in the pattern the music is now, 0…1. The only thing that moves.
    private(set) var playhead: Double = 0
    private(set) var trackMarkers: [TrackMarker] = []
    private(set) var currentTimeMs: Double = 0
    private(set) var currentBeatIndex: Int = 0
    private(set) var isFinished = false
    private(set) var phase: SessionPhase = .countIn
    /// How many times the figure has come round. It only ever goes up.
    private(set) var loopIndex: Int = 0
    /// Your best eight consecutive passes SO FAR, on the half and speed you are
    /// playing now — the same question the results screen answers, asked live.
    ///
    /// A best rather than a running accuracy, and that is the whole point: a
    /// live average falls on every mistake, which puts a dropping number in
    /// front of somebody in the middle of a figure and gives them something to
    /// watch that is not the instrument. This can only go up. Recomputed once
    /// per pass, never per frame.
    private(set) var bestSoFar: Double?
    
    // Live judgement feed (for debug / practice feedback)
    private(set) var lastJudgement: NoteJudgement?
    
    // Dependencies set before start
    var cue: CuePlayer?
    var metronomeEnabled = true
    var referenceToneEnabled = true
    var onComplete: ((SongResult?) -> Void)?
    /// "Kotekan Telu · Polos" — shown on the results screen.
    var sessionSubtitle = ""

    // Config
    private var song: Song = ResourceLoader.bundledSongs().first ?? Song(id: "", title: "", difficulty: .beginner, bpm: 60, requiredKeys: 0, durationMs: 0, notes: [])
    private var profile: InstrumentProfile?
    private var tempoScale: Double = 1
    
    // Play-mode state
    private var notes: [Note] = []
    private var judged: [Bool] = []
    /// How each of your notes turned out this loop — colours its trail on the
    /// river. Separate from `judged`, which the example also uses as a "fired".
    private var outcomes: [JudgementResult?] = []
    private var referencedNotes: Set<String> = []
    private var lastBeatIndex = -1

    /// Finished passes and every judgement, kept PER HALF and keyed on the
    /// song's id ("ubitannyendok-polos").
    ///
    /// Accuracy is a claim about one half, so mixing polos passes into a sangsih
    /// score would be meaningless — but simply clearing the history on a switch
    /// sets a trap: peek at the other side for one cycle, come back, and an
    /// otherwise good session reports nothing. Parking each half's history
    /// instead means a switch costs nothing and coming back restores what you
    /// had. `end()` reports the half you finished on.
    ///
    /// Keyed on the song id rather than on a `KotekanHalf` so the engine stays
    /// ignorant of what a half is — it is handed songs, and that is all it needs
    /// to know to keep two ledgers apart. SPEED is part of the key for the same
    /// reason the half is: eight cycles at half tempo and eight at 1.5× are not
    /// the same achievement, and averaging them describes neither.
    private var cyclesByPart: [String: [CycleScore]] = [:]
    private var judgementsByPart: [String: [NoteJudgement]] = [:]
    private var partKey: String { "\(song.id)@\(tempoScale)" }
    /// Notes that landed anywhere this session, either half — the one number
    /// that feeds the gangsa's grade, and the only running total worth putting
    /// in front of the player mid-session.
    private(set) var landedNotes = 0
    private var tally = CycleTally()
    /// Set when the half changes mid-pass. The pass is then dropped rather than
    /// banked — see `setHalf`.
    private var cycleVoided = false
    /// Your own strokes that have already sounded this pass, so the guide voice
    /// fires once each. Separate from `judged`, which means "scored".
    private var guideFired: [Bool] = []
    
    
    // The partner's half: sounded by the app, never judged (§7).
    private var partnerNotes: [Note] = []
    private var partnerFired: [Bool] = []
    /// The two voices you can silence. Learning a half often means hearing the
    /// other one alone first and putting yours back once the figure is in the
    /// hands — so each is a switch, not a fixed arrangement.
    ///
    /// YOUR half defaults to silent, because you are the one playing it: the app
    /// sounding it too would mask your own mistakes. Turning it on makes the app
    /// play along with you, which is how you check a figure you have half
    /// forgotten without leaving the screen — it replaces the demo that used to
    /// be a screen of its own.
    ///
    /// The gong is NOT on this list. The colotomic frame is what the cycle is
    /// measured against; silencing it leaves the figure floating free with
    /// nothing to be early or late against, and every judgement this engine
    /// makes becomes meaningless.
    var partnerAudible = true
    var yourVoiceAudible = false
    /// Stereo placement of the two halves, so they read as two players.
    private let yourPan: Float = -0.32
    private let partnerPan: Float = 0.32

    // Transient flash bookkeeping: keyIndex -> (kind, expiry host time)
    private var flashes: [Int: (FlashKind, Double)] = [:]
    
    private var startHostTime: Double = 0
    
    // Tunables
    /// How far ahead a stroke starts announcing itself, in BEATS.
    ///
    /// Beats rather than milliseconds so it tracks the tempo control: at 0.5×
    /// the ring takes twice as long in wall-clock terms, which is what slowing
    /// a figure down has to mean, and "four pulses out" goes on meaning the
    /// same thing at every speed. Four is about a second at the tempo the
    /// bundled figures are notated at.
    ///
    /// This is the clutter dial as well as the warning time — every stroke
    /// inside it is drawn — but not the SPEED dial. The speed is constant at
    /// any value, which is the whole point of the constant existing.
    private let approachBeats: Double = 4

    /// How many nested rings one bilah may carry.
    ///
    /// Two. One is a countdown; two is a countdown plus "and again straight
    /// after", which is the shape of a kotekan. Three rings on one bar stop
    /// being readable as distinct distances and start being a target.
    private let maxApproachRings = 2
    private let missWindowMs: Double = 200               // §5.1
    private let flashDuration: Double = 0.3
    
    // The count-in, in beats.
    //
    // HALF a colotomic cycle, and the colotomic phase is measured from the end
    // of it (see `colotomicIndex`) — so the count-in runs kempur → kajar → kajar
    // and lands the GONG exactly on the first slot of the figure.
    //
    // This was wrong before and did not show: 16 beats of count-in with the
    // pulse counted from zero put the figure's first slot on the kempur, with
    // the gong landing halfway through a 32-slot figure. Nothing on the old
    // scrolling river made that visible. On a static cycle the gong rule is
    // drawn straight through the pattern, and a figure that starts on the wrong
    // half of the colotomic cycle is immediately, obviously wrong.
    private let introBeats = 16
    /// Silent beats between loops. Zero: the figure repeats forever, so the gong
    /// has to land exactly on the turn of the cycle. Any gap here and the pulse
    /// walks away from the pattern a little more on every pass.
    private var loopGapBeats = 0
    
    private var introMs: Double = 0
    private var patternMs: Double = 0
    private var patternOriginMs: Double = 0
    private var lastLoopIndex = -1// 300ms fades (§13.5)
    
    // MARK: - Lifecycle
    
    func configure(song: Song, partner: Song? = nil, profile: InstrumentProfile,
                   tempoScale: Double) {
        self.song = song
        self.profile = profile
        self.tempoScale = max(0.25, tempoScale)
        self.cyclesByPart = [:]
        self.judgementsByPart = [:]
        self.landedNotes = 0
        self.tally = CycleTally()
        self.cycleVoided = false
        self.referencedNotes = []
        self.lastBeatIndex = -1
        self.flashes = [:]
        self.isFinished = false
        self.renderStates = [:]
        self.lastLoopIndex = -1
        self.phase = .countIn
        self.loopIndex = 0
        self.bestSoFar = nil
        self.playhead = 0
        self.currentTimeMs = 0
        loadHalves(song: song, partner: partner)
        recomputeTiming()
    }

    /// Swap which half you are playing WITHOUT stopping the clock.
    ///
    /// The gong keeps going, the cycle count keeps climbing and everything
    /// already scored is kept — you are changing seats, not starting again. The
    /// two halves of a kotekan are the same length at the same tempo, so
    /// `patternMs` and the pattern origin are unaffected and the swap lands
    /// mid-cycle without the pulse shifting under it.
    ///
    /// The pass in progress is written OFF, not half-scored. Its notes belonged
    /// to the other half, and the new half's strokes that are already behind the
    /// playhead auto-miss the instant they load — so banking it would drop a
    /// meaningless near-zero into the graph every time somebody changed sides.
    ///
    /// Everything else about the half you are leaving is parked, not discarded:
    /// see `cyclesByPart`.
    func setHalf(song: Song, partner: Song?) {
        self.song = song
        loadHalves(song: song, partner: partner)
        cycleVoided = true
        recomputeTiming()
        refreshBestSoFar()
    }

    private func loadHalves(song: Song, partner: Song?) {
        notes = song.notes.sorted { $0.timeMs < $1.timeMs }
        judged = Array(repeating: false, count: notes.count)
        outcomes = Array(repeating: nil, count: notes.count)
        guideFired = Array(repeating: false, count: notes.count)
        partnerNotes = (partner?.notes ?? []).sorted { $0.timeMs < $1.timeMs }
        partnerFired = Array(repeating: false, count: partnerNotes.count)
    }
    
    func start() {
        //R Booting the audio engine loads and decodes 13 samples, which took
        //R long enough that the clock had already run on without the cues.
        //R Start the cue player first, then stamp the clock.
        cue?.start()
        startHostTime = CACurrentMediaTime()
    }
    
    /// Change speed mid-session without the music jumping.
    ///
    /// Everything downstream is derived from `beatMs`, which tempo divides — so
    /// naively assigning it moves the pattern boundaries under a clock that has
    /// not moved. `currentTimeMs` stays put while `patternMs` shrinks, and going
    /// to 1.5× would throw the cycle counter forward by a third of the session
    /// and land the colotomic pulse somewhere unrelated to where the gong just
    /// was.
    ///
    /// So the clock is rebased instead: measure where we are in BEATS, which is
    /// the one position that should survive a tempo change, then move
    /// `startHostTime` so the new beat length puts us at the same beat. The
    /// fractional part carries too, so nothing re-triggers and nothing is
    /// skipped — the next beat simply arrives sooner or later than the last one
    /// did.
    func setTempoScale(_ scale: Double) {
        let next = min(2, max(0.25, scale))
        guard abs(next - tempoScale) > 0.001 else { return }
        let beatsElapsed = currentTimeMs / beatMs
        tempoScale = next
        recomputeTiming()
        startHostTime = CACurrentMediaTime() - beatsElapsed * beatMs / 1000
        //R The pass in progress spans two speeds, so it is not a fair reading of
        //R either. Same reasoning as a mid-pass change of half.
        cycleVoided = true
        refreshBestSoFar()
    }

    private var beatMs: Double { 60000.0 / Double(song.bpm) / tempoScale }

    /// Absorb a pause: shift the clock forward by how long the session was
    /// stopped, so the music picks up exactly where it left off instead of
    /// jumping forward to catch up with wall-clock time.
    ///
    /// The pass in progress is voided. The clock was frozen, so nothing
    /// auto-missed while you were away and the pass would otherwise bank as a
    /// clean one with a silence in the middle of it — which is not what
    /// happened. Same reasoning as a mid-pass change of half or of speed.
    func resumeAfterPause(seconds: Double) {
        startHostTime += seconds
        cycleVoided = true
    }

    /// Stop the session and hand back what was played.
    ///
    /// Only COMPLETED passes are reported. The one in progress when the player
    /// hits stop is discarded: it is a fragment of a figure, it would score as
    /// near-total failure on the notes it never reached, and it would land in
    /// the graph as a cliff at the end of every single session.
    func end() {
        guard !isFinished else { return }
        isFinished = true
        cue?.stop()
        onComplete?(SongResult(songTitle: song.title,
                               subtitle: sessionSubtitle,
                               judgements: judgementsByPart[partKey] ?? [],
                               cycles: cyclesByPart[partKey] ?? [],
                               landedNotes: landedNotes))
    }

    private func recomputeTiming() {
        introMs = Double(introBeats) * beatMs
        //R The loop has to be the figure's MUSICAL length (whole gong cycles),
        //R not the end of its last note — the last slots of a kotekan are often
        //R rests, and cutting them made every repeat land early and rush.
        let lastEnd = notes.map { Double($0.timeMs + $0.durationMs) }.max() ?? 0
        patternMs = max(Double(song.durationMs), lastEnd) / tempoScale + Double(loopGapBeats) * beatMs
        if patternMs <= 0 { patternMs = beatMs * 4 }
    }
    
    private func scaledTime(_ note: Note) -> Double { Double(note.timeMs) / tempoScale }

    /// Where an absolute beat sits in the 32-beat colotomic cycle, counted from
    /// the first slot of the figure rather than from the start of the session.
    /// Negative beats (the count-in) wrap, so the lead-in is the tail of a cycle
    /// rather than a separate thing.
    private func colotomicIndex(forBeat beat: Int) -> Int {
        let fromFigure = beat - introBeats
        return ((fromFigure % 32) + 32) % 32
    }
    
    // MARK: - Frame tick
    
    func tick(now: Double) {
        guard !isFinished else { return }
        currentTimeMs = (now - startHostTime) * 1000

        let beatMs = self.beatMs
        
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
            phase = .userTurn

            if idx != lastLoopIndex {
                //R Close the pass that just ended BEFORE the arrays are wiped —
                //R this is the one moment its score is final, and the turn of
                //R the cycle is also the only place a running total can be cut
                //R without splitting a note's judgement across two passes.
                if lastLoopIndex >= 0 { closeCycle(index: lastLoopIndex) }
                lastLoopIndex = idx
                tally = CycleTally(startMs: patternOriginMs)
                cycleVoided = false
                judged = Array(repeating: false, count: notes.count)
                outcomes = Array(repeating: nil, count: notes.count)
                guideFired = Array(repeating: false, count: notes.count)
                partnerFired = Array(repeating: false, count: partnerNotes.count)
                flashes = [:]
            }
        }
        _ = previousPhase

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
            //R Unconditional. The colotomic frame is what everything else is
            //R measured against — silence it and the figure floats free, with
            //R nothing to be early or late against.
            switch colotomicIndex(forBeat: beatIndex) {
            case 0:
                cue?.playGong()
                cue?.playKajar()

            case 4, 8, 12:
                cue?.playKajar()

            case 16:
                cue?.playKempur()
                cue?.playKajar()

            case 20, 24, 28:
                cue?.playKajar()

            default:
                break
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
        case .userTurn:
            //R Judge first, so a note retired this frame doesn't also get cued.
            tickPlay(now: now, patternTime: patternTime, states: &states)
            tickUserTurnCue(patternTime: patternTime, beatMs: beatMs, states: &states)
            tickGuide(patternTime: patternTime)
        }

        renderStates = states
        playhead = patternMs > 0 ? min(1, max(0, patternTime / patternMs)) : 0
        rebuildTrack(patternTime: patternTime, beatMs: beatMs)
    }

    /// Bank the pass that just ended.
    private func closeCycle(index: Int) {
        guard !cycleVoided, tally.noteCount > 0 else { return }
        cyclesByPart[partKey, default: []].append(
            CycleScore(index: index,
                       startMs: tally.startMs,
                       noteCount: tally.noteCount,
                       score: tally.score,
                       onBeat: tally.onBeat,
                       mistakes: tally.mistakes))
        refreshBestSoFar()
    }

    /// The live best, recomputed from the ledger for whatever half and speed is
    /// current. Called when a pass closes and whenever the ledger changes under
    /// the session — switching sides or speed parks one and picks up another,
    /// and the number in the bar has to follow.
    private func refreshBestSoFar() {
        bestSoFar = SongResult.bestWindow(in: cyclesByPart[partKey] ?? [])?.accuracy
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
    
    //R --------------------------------------------------------------------
    //R "Your turn" cue.
    //R
    //R The bilah and the score are both mapped from the same clock, so the rule
    //R is simply: whichever stroke is due, that bilah is lit. The note that has
    //R just arrived holds a solid highlight, then releases in time for the next
    //R note's ring to read (otherwise a 4→4 repeat looks like one long
    //R highlight). Nothing here waits on onset detection — that hold was what
    //R pinned the highlight to one bilah while the figure moved on.
    //R --------------------------------------------------------------------

    /// The note the overlay is showing as due: the latest one whose time has
    /// arrived. `notes` is sorted, so scan forward and keep the last match.
    private func currentNoteIndex(patternTime: Double) -> Int? {
        var current: Int?
        for i in notes.indices {
            guard scaledTime(notes[i]) <= patternTime else { break }
            current = i
        }
        if let current, judged[current] { return nil }   // already hit or missed
        return current
    }

    private func tickUserTurnCue(patternTime: Double, beatMs: Double, states: inout [Int: KeyRenderState]) {
        let window = approachBeats * beatMs

        //R EVERY stroke inside the window, not just the next one.
        //R
        //R This used to cue one note at a time over a window equal to the GAP
        //R since the previous stroke, which made the ring's speed a property of
        //R the figure instead of of the clock. On Ubitan Nyendok the gaps
        //R alternate 500 ms and 250 ms, so the ring closed at two different
        //R rates on alternate strokes and its size stopped meaning anything —
        //R which is exactly what it is for.
        //R
        //R Cueing only the next note is what forced that. A window longer than
        //R the gap cannot start on time if the ring is not allowed to exist
        //R until the previous stroke is out of the way: it would appear already
        //R half closed and only travel the remainder. A fixed window needs
        //R every note in it.
        //R
        //R Repetition 1 is the next time round. Without it the cue went dead
        //R for the last 500 ms of every pass — the tail of a kotekan is usually
        //R rests, so there was no "next note" left to point at and the figure
        //R came round with no warning at all.
        var pending: [Int: [Double]] = [:]
        for repetition in 0...1 {
            let origin = Double(repetition) * patternMs
            for i in notes.indices {
                //R Judged means struck or missed, and only ever applies to THIS
                //R pass; the same stroke one repetition ahead is still to come.
                if repetition == 0, judged[i] { continue }
                let until = scaledTime(notes[i]) + origin - patternTime
                guard until > 0, until <= window else { continue }
                pending[notes[i].keyIndex, default: []].append(1 - until / window)
            }
        }

        for (key, progresses) in pending {
            //R Nearest first — highest progress is the one closest to landing.
            //R Anything past the second is dropped rather than drawn small: see
            //R `maxApproachRings`.
            let nearest = Array(progresses.sorted(by: >).prefix(maxApproachRings))
            var s = states[key] ?? KeyRenderState()
            s.approaches = nearest
            //R The bar that fills from the bottom follows the NEAREST stroke
            //R only. There is one of it per bilah and it is a "how soon",
            //R which two strokes cannot both answer.
            s.fill = max(s.fill, nearest.first ?? 0)
            states[key] = s
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

    /// Your own half, played back beside you when you ask for it.
    ///
    /// This is what is left of the demo screen. Watching the figure used to mean
    /// leaving the instrument and going somewhere else to hear it; now it is a
    /// switch you flip mid-practice, the cycle never stops, and you can turn it
    /// off again the moment the shape comes back to you.
    ///
    /// It never touches judgement. The bilah still light from the clock and your
    /// strikes are still scored against it, so playing along with the guide is
    /// scored exactly like playing without it.
    private func tickGuide(patternTime: Double) {
        guard yourVoiceAudible, !notes.isEmpty else { return }
        for i in notes.indices where !guideFired[i] {
            let until = scaledTime(notes[i]) - patternTime
            if until <= 0, until > -60 {
                guideFired[i] = true
                cue?.playKeySample(index: notes[i].keyIndex, pan: yourPan)
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
    
    // MARK: - Strike handling (from AudioEngineController, main queue)
    
    func registerStrike(keyIndex: Int, hostTime: Double, confidence: Double) {
        guard !isFinished, phase.isUserPlaying else { return }
        registerPlayStrike(keyIndex: keyIndex, hostTime: hostTime)
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
    
    // MARK: - The river (§13.5)

    /// Builds one frame of the score: the figure laid out across one pattern,
    /// and the colotomic pulse that falls inside this pass.
    ///
    /// Nothing here moves. Positions are `time / patternMs`, fixed for as long
    /// as the figure is, so the shape on screen is the shape you are learning —
    /// `playhead` is the only value that changes, and NotesRiver sweeps a line
    /// with it.
    ///
    /// The pulse markers ARE rebuilt every frame, and have to be: the colotomic
    /// cycle is 32 beats while a figure may be 8, 16 or 32 slots long, so a
    /// short figure goes round several times per gong and the gong lands on a
    /// different pass each time. Placing them from the absolute beat index is
    /// what keeps that honest — on Ubitan Nyendok the gong dot correctly shows
    /// up on one pass in four rather than on every one.
    private func rebuildTrack(patternTime: Double, beatMs: Double) {
        guard patternMs > 0 else { trackMarkers = []; cycleNotes = []; return }

        var marks: [TrackMarker] = []
        let firstBeat = Int((patternOriginMs / beatMs).rounded(.down))
        let lastBeat = Int(((patternOriginMs + patternMs) / beatMs).rounded(.up))
        if lastBeat >= firstBeat {
            for b in firstBeat...lastBeat {
                let x = (Double(b) * beatMs - patternOriginMs) / patternMs
                guard x >= 0, x < 1 else { continue }
                marks.append(TrackMarker(id: b * 10 + 1, kind: .kajar, xFraction: x))
                switch colotomicIndex(forBeat: b) {
                case 0:  marks.append(TrackMarker(id: b * 10 + 2, kind: .gong, xFraction: x))
                case 16: marks.append(TrackMarker(id: b * 10 + 2, kind: .kempur, xFraction: x))
                default: break
                }
            }
        }
        trackMarkers = marks

        // The figure appears once the gong has established the cycle.
        guard phase != .countIn else { cycleNotes = []; return }

        func width(_ note: Note) -> Double {
            min(0.25, Double(note.durationMs) / tempoScale / patternMs)
        }

        let current = currentNoteIndex(patternTime: patternTime)
        var out: [CycleNote] = []
        out.reserveCapacity(notes.count + partnerNotes.count)

        for i in notes.indices {
            out.append(CycleNote(id: "y-\(notes[i].id)",
                                 keyIndex: notes[i].keyIndex,
                                 voice: .yours,
                                 x: scaledTime(notes[i]) / patternMs,
                                 width: width(notes[i]),
                                 outcome: outcomes[i],
                                 isCurrent: i == current))
        }
        for i in partnerNotes.indices {
            out.append(CycleNote(id: "p-\(partnerNotes[i].id)",
                                 keyIndex: partnerNotes[i].keyIndex,
                                 voice: .partner,
                                 x: scaledTime(partnerNotes[i]) / patternMs,
                                 width: width(partnerNotes[i])))
        }
        cycleNotes = out
    }

    // MARK: - Helpers
    
    private func record(_ result: JudgementResult, at key: Int, now: Double, playSound: Bool, timingErrorMs: Double = 0, storeResult: Bool = true) {
        let judgement = NoteJudgement(keyIndex: key, result: result, timingErrorMs: timingErrorMs)
        if storeResult {
            judgementsByPart[partKey, default: []].append(judgement)
            if result.onBeat { landedNotes += 1 }
            //R The pass in progress, tallied as it goes. Banked at the turn of
            //R the cycle by `closeCycle` — see there for why only whole passes
            //R reach the graph.
            tally.noteCount += 1
            tally.score += result.score
            if result.onBeat { tally.onBeat += 1 }
            if result == .miss || result == .wrongKey { tally.mistakes += 1 }
        }
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
    
}

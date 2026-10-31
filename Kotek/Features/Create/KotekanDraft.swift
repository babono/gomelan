//
//  KotekanDraft.swift
//  Kotek
//
//  The figure being made in Create Kotek, shared by every step of the flow:
//  the piano roll writes it (by tap or from the sensors), the review screen
//  corrects it, and Save turns it into a `Kotekan`.
//
//  Positions are TICKS, 96 to the quarter, not grid slots. Gamelan is played
//  straight, so the piano roll snaps from a whole bar down to a quarter and
//  nothing else: no triplets, no dots. It went down to an 8th; at a
//  touchable zoom an 8th cell was too thin to aim at.
//
//  A BEAT is the value labelled 1: one bar of the roll, which the snap menu
//  divides into 2 and 4. The engine counts a grid slot per stroke, so
//  `kotekan(id:)` makes a slot a quarter of a beat, and BPM here is beats per
//  minute — a slot's rate divided by four.
//
//  The gong, kempur, klentong and kajar are not written. They were — armed as
//  tools and tapped onto the roll — and every figure ended up with the same
//  line drawn by hand. Now `colotomic` lays the common cycle under whatever
//  is written: gong, kempur, klentong, kempur, one per beat, a kajar on each.
//

import Foundation
import Observation

/// A note value the piano roll snaps to: 1 is a whole bar, 4 a quarter.
struct Subdivision: Hashable, Identifiable {
    var denominator: Int

    static let denominators = [1, 2, 4]

    static let quarter = Subdivision(denominator: 4)

    var id: Int {
        denominator
    }

    var ticks: Int {
        KotekanDraft.ticksPerBar / denominator
    }

    var label: String {
        denominator == 1 ? "1" : "1/\(denominator)"
    }
}

/// One stroke. `length` is how long the player means it to ring — written at
/// the snap value, then dragged longer or shorter on the piano roll. The
/// engine only reads `tick`: a bilah rings until it is damped.
struct DraftNote: Hashable, Identifiable {
    var id = UUID()
    var half: KotekanHalf
    var key: Int
    var tick: Int
    var length: Int
}

/// A gong, kempur, klentong or kajar stroke, drawn as a circle on the line it sits on.
struct DraftColotomic: Hashable {
    var instrument: ColotomicInstrument
    var tick: Int
}

@Observable
final class KotekanDraft {
    static let ticksPerQuarter = 96
    static let ticksPerBar = ticksPerQuarter * 4
    /// One BPM beat: the value labelled 1.
    static let ticksPerBeat = ticksPerBar
    /// How far the piano roll scrolls. The figure itself is `bars` long and
    /// grows when a note is written past its end; this is just the room.
    static let timelineBars = 32
    static let bpmRange = 1 ... 999

    /// Empty until the player names it on Save; `kotekan(id:)` falls back to
    /// "My kotekan" if they never do.
    var name = ""
    var source: KotekanSource = .manual
    /// Beats per minute, a beat being the value labelled 1. Four grid slots to
    /// the beat, so the database's per-slot `bpm` is four times this.
    /// ponytail: no control for it — a new figure is 100, an opened one keeps
    /// the tempo it was saved at.
    var bpm = 100
    private(set) var notes: [DraftNote] = []

    /// The colotomic cycle under the figure, one beat at a time: gong, kempur,
    /// klentong, kempur, then gong again, and a kajar on every beat.
    var colotomic: [DraftColotomic] {
        (0 ..< bars).flatMap { beat in
            Self.colotomic(atBeat: beat).map { DraftColotomic(instrument: $0, tick: beat * Self.ticksPerBeat) }
        }
    }

    /// What sounds on `beat`. Also read straight by the recording, which runs
    /// on past the end of the figure.
    static func colotomic(atBeat beat: Int) -> [ColotomicInstrument] {
        let cycle: [ColotomicInstrument] = [.gong, .kempur, .klentong, .kempur]
        return [cycle[beat % cycle.count], .kajar]
    }

    /// What the figure looked like before each edit, newest last. The name is
    /// not in it: it is a field the player can see and set back.
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    /// Whole bars up to the last thing written. Not set by hand: a Bars stepper
    /// was one more control for something the notes already say, and it cut
    /// notes off when stepped down.
    var bars: Int {
        // A note's end counts too, so one dragged across a bar line takes the
        // figure with it.
        let last = notes.map { $0.tick + $0.length - 1 }.max() ?? 0
        return last / Self.ticksPerBar + 1
    }

    var lengthTicks: Int {
        bars * Self.ticksPerBar
    }

    static var timelineTicks: Int {
        timelineBars * ticksPerBar
    }

    /// No strokes: nothing to save, and nothing to play.
    var isEmpty: Bool {
        notes.isEmpty
    }

    // MARK: - Editing

    func notes(_ half: KotekanHalf) -> [DraftNote] {
        notes.filter { $0.half == half }
    }

    /// The piano roll's tap: remove the note under the finger, or write one.
    ///
    /// A half is one mallet, so it strikes one bilah at a time — writing a note
    /// replaces whatever that half already had starting on the same tick.
    ///
    /// Writing past the end of the figure stretches it to the bar the note is
    /// in, the way a DAW region grows when you draw beyond it.
    func toggle(half: KotekanHalf, key: Int, at position: Int, snap: Subdivision) {
        if let hit = notes.firstIndex(where: {
            $0.half == half && $0.key == key && $0.tick <= position && position < $0.tick + $0.length
        }) {
            notes.remove(at: hit)
            return
        }
        let tick = position / snap.ticks * snap.ticks
        guard tick < Self.timelineTicks else { return }
        set(half: half, tick: tick, key: key, length: min(snap.ticks, Self.timelineTicks - tick))
    }

    /// Write `key` (or a rest) at exactly `tick`. Used by the review grid and
    /// the sensors, which both write at a given place rather than a tap's.
    func set(half: KotekanHalf, tick: Int, key: Int?, length: Int? = nil) {
        notes.removeAll { $0.half == half && $0.tick == tick }
        guard let key else { return }
        notes.append(DraftNote(half: half, key: key, tick: tick, length: length ?? slotTicks))
    }

    /// Stretch or shorten a stroke, from the handle on its end. Never past the
    /// next stroke of the same half — a half is one mallet, so its next stroke
    /// is where this one is damped — nor past the end of the timeline.
    func resize(_ id: DraftNote.ID, length: Int) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        let note = notes[i]
        let next = notes
            .filter { $0.half == note.half && $0.tick > note.tick }
            .map(\.tick).min() ?? Self.timelineTicks
        notes[i].length = length.clamped(to: 1, next - note.tick)
    }

    func length(of id: DraftNote.ID) -> Int? {
        notes.first { $0.id == id }?.length
    }

    /// Take out the stroke on `key` under the finger — the half being written
    /// first, then the other, since the Delete tool should remove whatever the
    /// player can see there.
    func eraseNote(key: Int, at position: Int, preferring half: KotekanHalf) {
        for h in [half, half.other] {
            if let hit = notes.firstIndex(where: {
                $0.half == h && $0.key == key && $0.tick <= position && position < $0.tick + $0.length
            }) {
                notes.remove(at: hit)
                return
            }
        }
    }

    // MARK: - Undo

    private struct Snapshot: Equatable {
        var notes: [DraftNote]
    }

    private var snapshot: Snapshot {
        Snapshot(notes: notes)
    }

    /// The figure as it was when a group began; edits inside it are not
    /// steps of their own.
    private var groupStart: Snapshot?

    /// Not mid-group: an undo then would step back past the group's start.
    var canUndo: Bool {
        groupStart == nil && !undoStack.isEmpty
    }

    var canRedo: Bool {
        groupStart == nil && !redoStack.isEmpty
    }

    /// Run `change` as one step of undo. A tap that changed nothing is none.
    func edit(_ change: () -> Void) {
        let before = snapshot
        change()
        guard groupStart == nil else { return }
        push(before)
    }

    /// Everything until `endGroup()` is one step of undo — a recording take,
    /// which is one gesture however many strokes it writes.
    func beginGroup() {
        groupStart = snapshot
    }

    func endGroup() {
        guard let start = groupStart else { return }
        groupStart = nil
        push(start)
    }

    private func push(_ before: Snapshot) {
        guard snapshot != before else { return }
        undoStack.append(before)
        // ponytail: a cap rather than anything cleverer. 200 taps back is
        // further than anyone scrubs.
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard groupStart == nil, let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        restore(previous)
    }

    func redo() {
        guard groupStart == nil, let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        restore(next)
    }

    private func restore(_ s: Snapshot) {
        notes = s.notes
    }

    // MARK: - From a kotekan

    /// Open a saved figure for editing: its grid back onto the piano roll.
    ///
    /// A saved figure keeps only slots and milliseconds per slot. A slot comes
    /// back as a quarter of a beat. Its colotomic line is not read back: the
    /// cycle is laid under it again from its length.
    func load(_ k: Kotekan) {
        name = k.name
        source = k.source
        let slot = Subdivision.quarter.ticks
        bpm = Self.bpm(strokeMs: k.strokeMs, slotTicks: slot).clamped(
            to: Self.bpmRange.lowerBound,
            Self.bpmRange.upperBound
        )
        notes = [(KotekanHalf.polos, k.polos), (.sangsih, k.sangsih)].flatMap { half, grid in
            grid.enumerated().compactMap { i, key in
                key.map { DraftNote(half: half, key: $0, tick: i * slot, length: slot) }
            }
        }
        undoStack = []
        redoStack = []
    }

    private static func bpm(strokeMs: Int, slotTicks: Int) -> Int {
        guard strokeMs > 0 else { return 100 }
        return Int((60000.0 * Double(slotTicks) / (Double(ticksPerBeat) * Double(strokeMs))).rounded())
    }

    // MARK: - As a kotekan

    /// Ticks per engine slot: a quarter, unless a stroke was written off it (the
    /// sensors can) — then the coarsest step every one lands on.
    var slotTicks: Int {
        notes.map(\.tick).reduce(Subdivision.quarter.ticks) { gcd($0, $1) }
    }

    var slotCount: Int {
        lengthTicks / slotTicks
    }

    func grid(_ half: KotekanHalf) -> [Int?] {
        var grid = [Int?](repeating: nil, count: slotCount)
        for note in notes where note.half == half {
            grid[note.tick / slotTicks] = note.key
        }
        return grid
    }

    /// Milliseconds from the top of the figure to `tick` at `bpm`.
    func ms(atTick tick: Double) -> Double {
        tick / Double(Self.ticksPerBeat) * 60000 / Double(bpm)
    }

    /// Milliseconds per engine slot at `bpm`.
    var strokeMs: Int {
        Int((60000.0 / Double(bpm) * Double(slotTicks) / Double(Self.ticksPerBeat)).rounded())
    }

    func kotekan(id: String) -> Kotekan {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Kotekan(
            id: id,
            name: trimmed.isEmpty ? "My kotekan" : trimmed,
            level: 0,
            source: source,
            toneLabel: source == .automatic ? "Recorded" : "Your kotekan",
            blurb: "",
            polos: grid(.polos),
            sangsih: grid(.sangsih),
            strokeMs: strokeMs,
            colotomic: colotomic.map { ColotomicHit(slot: $0.tick / slotTicks, instrument: $0.instrument) }
        )
    }
}

private func gcd(_ a: Int, _ b: Int) -> Int {
    b == 0 ? a : gcd(b, a % b)
}

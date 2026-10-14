//
//  KotekanDraft.swift
//  Kotek
//
//  The figure being made in Create Kotek, shared by every step of the flow:
//  the piano roll writes it (by tap or from the sensors), the review screen
//  corrects it, and Save turns it into a `Kotekan`.
//
//  Positions are TICKS, 96 to the quarter, not grid slots. The piano roll snaps
//  to anything from 1/2 to 1/32 including triplets and dots, and 96 is the
//  smallest count that puts every one of those on a whole number (a 1/32
//  triplet is 8, a dotted 1/32 is 18). A slot grid would have to pick its
//  resolution before the player had written a note.
//
//  The engine still wants slots, so `kotekan(id:)` picks the coarsest grid
//  every note sits on — a 16th for anything written straight, which is what
//  every bundled figure uses.
//

import Foundation
import Observation

/// A note value the piano roll snaps to.
struct Subdivision: Hashable, Identifiable {
    enum Feel: String, CaseIterable {
        case straight, triplet, dotted
    }

    var denominator: Int
    var feel: Feel = .straight

    static let denominators = [2, 4, 8, 16, 32]
    static let sixteenth = Subdivision(denominator: 16)

    var id: String {
        label
    }

    var ticks: Int {
        let base = KotekanDraft.ticksPerBar / denominator
        switch feel {
        case .straight: return base
        case .triplet: return base * 2 / 3
        case .dotted: return base * 3 / 2
        }
    }

    var label: String {
        switch feel {
        case .straight: "1/\(denominator)"
        case .triplet: "1/\(denominator) T"
        case .dotted: "1/\(denominator) ·"
        }
    }
}

/// One stroke. `length` is only how wide the piano roll draws it — a bilah
/// rings until it is damped, so the engine only ever reads `tick`.
struct DraftNote: Hashable, Identifiable {
    var id = UUID()
    var half: KotekanHalf
    var key: Int
    var tick: Int
    var length: Int
}

/// A gong, kajar or klentong stroke, drawn as a circle on the line it sits on.
struct DraftColotomic: Hashable {
    var instrument: ColotomicInstrument
    var tick: Int
}

@Observable
final class KotekanDraft {
    static let ticksPerQuarter = 96
    static let ticksPerBar = ticksPerQuarter * 4
    /// How far the piano roll scrolls. The figure itself is `bars` long and
    /// grows when a note is written past its end; this is just the room.
    static let timelineBars = 32
    static let bpmRange = 40 ... 200

    /// Empty until the player names it on Save; `kotekan(id:)` falls back to
    /// "My kotekan" if they never do.
    var name = ""
    var source: KotekanSource = .manual
    /// Quarter notes per minute, as in any DAW. Not the per-slot number the
    /// database stores — `strokeMs` converts.
    var bpm = 88
    private(set) var notes: [DraftNote] = []
    private(set) var colotomic: [DraftColotomic] = []

    /// What the figure looked like before each edit, newest last. The tempo
    /// and the name are not in it: they are fields the player can see and set
    /// back, and an Undo that silently moved the tempo would be a surprise.
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    /// Whole bars up to the last thing written. Not set by hand: a Bars stepper
    /// was one more control for something the notes already say, and it cut
    /// notes off when stepped down.
    var bars: Int {
        let last = (notes.map(\.tick) + colotomic.map(\.tick)).max() ?? 0
        return last / Self.ticksPerBar + 1
    }

    var lengthTicks: Int {
        bars * Self.ticksPerBar
    }

    static var timelineTicks: Int {
        timelineBars * ticksPerBar
    }

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

    /// Add or take out a colotomic stroke. It snaps to the NEAREST line rather
    /// than the one before the finger, since the circle is drawn on the line.
    func toggleColotomic(_ instrument: ColotomicInstrument, at position: Int, snap: Subdivision) {
        if let hit = colotomic.firstIndex(where: {
            $0.instrument == instrument && abs($0.tick - position) <= snap.ticks / 2
        }) {
            colotomic.remove(at: hit)
            return
        }
        let tick = Int((Double(position) / Double(snap.ticks)).rounded()) * snap.ticks
        guard tick < Self.timelineTicks else { return }
        colotomic.append(DraftColotomic(instrument: instrument, tick: tick))
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

    /// Take out the gong, kajar or klentong nearest the finger, if one is
    /// within `tolerance` ticks.
    func eraseColotomic(near position: Int, tolerance: Int) {
        guard let nearest = colotomic.indices.min(by: {
            abs(colotomic[$0].tick - position) < abs(colotomic[$1].tick - position)
        }), abs(colotomic[nearest].tick - position) <= tolerance else { return }
        colotomic.remove(at: nearest)
    }

    // MARK: - Undo

    private struct Snapshot: Equatable {
        var notes: [DraftNote]
        var colotomic: [DraftColotomic]
    }

    private var snapshot: Snapshot {
        Snapshot(notes: notes, colotomic: colotomic)
    }

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    /// Run `change` as one step of undo. A tap that changed nothing is none.
    func edit(_ change: () -> Void) {
        let before = snapshot
        change()
        guard snapshot != before else { return }
        undoStack.append(before)
        // ponytail: a cap rather than anything cleverer. 200 taps back is
        // further than anyone scrubs.
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        restore(next)
    }

    private func restore(_ s: Snapshot) {
        notes = s.notes
        colotomic = s.colotomic
    }

    // MARK: - From a kotekan

    /// Open a saved figure for editing: its grid back onto the piano roll.
    ///
    /// A saved figure keeps only slots and milliseconds per slot, not the snap
    /// it was written at, so the slot is read as the longest note value that
    /// puts the tempo inside `bpmRange` — a 16th for anything written
    /// straight, which gives back exactly what was saved.
    func load(_ k: Kotekan) {
        name = k.name
        source = k.source
        let candidates = [Subdivision.sixteenth.ticks, 16, 12, 8, 6, 4, 3]
        let slot = candidates.first { ticks in
            Self.bpmRange.contains(Self.bpm(strokeMs: k.strokeMs, slotTicks: ticks))
        } ?? Subdivision.sixteenth.ticks
        bpm = min(
            max(Self.bpm(strokeMs: k.strokeMs, slotTicks: slot), Self.bpmRange.lowerBound),
            Self.bpmRange.upperBound
        )
        notes = [(KotekanHalf.polos, k.polos), (.sangsih, k.sangsih)].flatMap { half, grid in
            grid.enumerated().compactMap { i, key in
                key.map { DraftNote(half: half, key: $0, tick: i * slot, length: slot) }
            }
        }
        colotomic = k.colotomic.map { DraftColotomic(instrument: $0.instrument, tick: $0.slot * slot) }
        undoStack = []
        redoStack = []
    }

    private static func bpm(strokeMs: Int, slotTicks: Int) -> Int {
        guard strokeMs > 0 else { return 88 }
        return Int((60000.0 * Double(slotTicks) / (Double(ticksPerQuarter) * Double(strokeMs))).rounded())
    }

    // MARK: - As a kotekan

    /// Ticks per engine slot: the coarsest step every note lands on.
    ///
    /// Starts from a 16th rather than from the bar, so a sparse figure written
    /// in quarters still plays on the 16-slot grid the bundled figures use —
    /// the engine's kajar falls every 4 slots, which is only a beat if a slot
    /// is a 16th.
    ///
    /// ponytail: anything finer than a 16th (triplets, 1/32) shrinks the slot,
    /// and the engine's 32-slot gong cycle then no longer lands on a bar line.
    /// Fine for practising the figure; revisit if the colotomic layer has to
    /// follow the bar.
    var slotTicks: Int {
        let ticks = notes.map(\.tick) + colotomic.map(\.tick)
        return ticks.reduce(Subdivision.sixteenth.ticks) { gcd($0, $1) }
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
        tick / Double(Self.ticksPerQuarter) * 60000 / Double(bpm)
    }

    /// Milliseconds per engine slot at `bpm`.
    var strokeMs: Int {
        Int((60000.0 / Double(bpm) * Double(slotTicks) / Double(Self.ticksPerQuarter)).rounded())
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

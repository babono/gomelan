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
//  line drawn by hand. Now `colotomic` lays a cycle under whatever is
//  written, from one of two templates (`ColotomicTemplate`), and the figure
//  runs to whole cycles of it so each pass ends where the cycle does.
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

/// One stroke. `length` is where the player damps it, dragged on the piano
/// roll; nil — every stroke as written — rings until the half's next stroke,
/// as a gangsa player damps each bilah as they strike the next. That is the
/// rule the waterfall draws its damp cap by (`PlayEngine.fallingNotes`).
///
/// It used to be written at the snap value, a block one cell long, with a grip
/// to drag it out — and nothing read the length but the roll, so a
/// quarter-long block said the bilah was stopped where the player would in
/// fact let it ring. A dragged damp point is saved now (`Kotekan.polosDamp`,
/// `kotekan_hits.damp_slots`) and played.
struct DraftNote: Hashable, Identifiable {
    var id = UUID()
    var half: KotekanHalf
    var key: Int
    var tick: Int
    var length: Int?
}

/// How long a stroke rings on the roll, and whether it ends in a damp.
struct DraftRing: Equatable {
    var ticks: Int
    /// Stopped by the hand rather than struck again: the next stroke of the
    /// half is another bilah, or the player damped it before that.
    var damps: Bool
}

/// The colotomic cycle the player picks in Studio, one instrument per beat.
enum ColotomicTemplate: String, CaseIterable, Identifiable {
    /// Four beats: kempur, kajar, klentong, kajar.
    case four
    /// Eight beats: four kajar, then gong, kempur, kajar, kempur.
    case eight

    var id: String {
        rawValue
    }

    var cycle: [ColotomicInstrument] {
        switch self {
        case .four: [.kempur, .kajar, .klentong, .kajar]
        case .eight: [.kajar, .kajar, .kajar, .kajar, .gong, .kempur, .kajar, .kempur]
        }
    }

    var title: String {
        switch self {
        case .four: String(localized: "4 beats")
        case .eight: String(localized: "8 beats")
        }
    }
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
    /// Typed in Studio's controls row (`BPMField`); a new figure starts at
    /// 100, an opened one at the tempo it was saved at.
    var bpm = 100
    private(set) var notes: [DraftNote] = []

    /// Which cycle runs under the figure. A saved figure's hits are not read
    /// back into it (see `load`), so an opened one starts on the 4-beat one.
    var template = ColotomicTemplate.four

    /// The colotomic cycle under the figure, one beat at a time.
    var colotomic: [DraftColotomic] {
        (0 ..< bars).flatMap { beat in
            colotomic(atBeat: beat).map { DraftColotomic(instrument: $0, tick: beat * Self.ticksPerBeat) }
        }
    }

    /// What sounds on `beat`. Also read straight by the recording, which runs
    /// on past the end of the figure.
    func colotomic(atBeat beat: Int) -> [ColotomicInstrument] {
        let cycle = template.cycle
        return [cycle[beat % cycle.count]]
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
        // A ringing stroke does not: it would run the figure on forever.
        let last = notes.map { $0.tick + ($0.length ?? 1) - 1 }.max() ?? 0
        let written = last / Self.ticksPerBar + 1
        // Up to whole cycles: a 2-beat figure over the 8-beat template looped
        // back to its start before the gong ever came round.
        let cycle = template.cycle.count
        return (written + cycle - 1) / cycle * cycle
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
    /// Only the stroke's own cell takes it out, not the whole of its ring: a
    /// stroke rings to the next one, so a tap further along its row is
    /// striking that bilah again, not undoing the first.
    ///
    /// Writing past the end of the figure stretches it to the bar the note is
    /// in, the way a DAW region grows when you draw beyond it.
    func toggle(half: KotekanHalf, key: Int, at position: Int, snap: Subdivision) {
        if let hit = notes.firstIndex(where: {
            $0.half == half && $0.key == key && $0.tick <= position && position < $0.tick + snap.ticks
        }) {
            notes.remove(at: hit)
            return
        }
        let tick = position / snap.ticks * snap.ticks
        guard tick < Self.timelineTicks else { return }
        set(half: half, tick: tick, key: key)
    }

    /// Write `key` (or a rest) at exactly `tick`. Used by the review grid and
    /// the sensors, which both write at a given place rather than a tap's.
    func set(half: KotekanHalf, tick: Int, key: Int?) {
        notes.removeAll { $0.half == half && $0.tick == tick }
        guard let key else { return }
        notes.append(DraftNote(half: half, key: key, tick: tick))
    }

    /// The damp grip's step, and the shortest a stroke rings: one block, a
    /// quarter, whatever the snap. A block is one stroke's room to be struck
    /// and stopped before the same bilah is struck again on the next.
    ///
    /// Half a block was tried, to pinch a bilah inside its own block for a
    /// fast repeated note. A player cannot damp that fast, and the block
    /// already is that note.
    static let dampStep = Subdivision.quarter.ticks

    /// Damp a stroke earlier, or let it ring longer, from the grip on its end.
    /// Never past the next stroke of the same half — a half is one mallet, so
    /// its next stroke stops this one anyway — and never under one block.
    /// Dragged all the way there it goes back to the default, and follows the
    /// next stroke if that moves.
    func resize(_ id: DraftNote.ID, length: Int) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        let gap = gap(after: notes[i])
        notes[i].length = length >= gap ? nil : max(Self.dampStep, length)
    }

    /// Put a stored damp point back as it was — nil for the default. The
    /// grip's undo step, which `resize` can't do: it clamps.
    func setDampPoint(_ id: DraftNote.ID, _ length: Int?) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].length = length
    }

    /// Ticks to the half's next stroke, or to the end of the figure.
    private func gap(after note: DraftNote) -> Int {
        let next = notes
            .filter { $0.half == note.half && $0.tick > note.tick }
            .map(\.tick).min() ?? max(lengthTicks, note.tick + 1)
        return next - note.tick
    }

    /// How long each stroke rings, keyed by id. Its own pass over the notes
    /// rather than `gap` per note: the roll asks for every one each frame.
    ///
    /// The last stroke of a half rings to the end of the figure, and is damped
    /// if the figure, going round, comes back in on another bilah.
    static func rings(_ notes: [DraftNote], patternTicks: Int) -> [DraftNote.ID: DraftRing] {
        var out: [DraftNote.ID: DraftRing] = [:]
        for half in [KotekanHalf.polos, .sangsih] {
            let strokes = notes.filter { $0.half == half }.sorted { $0.tick < $1.tick }
            for (i, note) in strokes.enumerated() {
                let next = i + 1 < strokes.count ? strokes[i + 1] : nil
                let gap = max(1, (next?.tick ?? patternTicks) - note.tick)
                let nextKey = (next ?? strokes[0]).key
                let ticks = min(note.length ?? gap, gap)
                out[note.id] = DraftRing(ticks: ticks, damps: ticks < gap || nextKey != note.key)
            }
        }
        return out
    }

    /// Take out the stroke on `key` under the finger — the half being written
    /// first, then the other, since the Delete tool should remove whatever the
    /// player can see there.
    func eraseNote(key: Int, at position: Int, preferring half: KotekanHalf) {
        for h in [half, half.other] {
            let rings = Self.rings(notes, patternTicks: lengthTicks)
            if let hit = notes.firstIndex(where: {
                $0.half == h && $0.key == key && $0.tick <= position
                    && position < $0.tick + (rings[$0.id]?.ticks ?? 1)
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
    /// back as a quarter of a beat, and a damp point as that many slots. Its
    /// colotomic line is not read back: the cycle is laid under it again from
    /// its length.
    func load(_ k: Kotekan) {
        name = k.name
        source = k.source
        let slot = Subdivision.quarter.ticks
        bpm = Self.bpm(strokeMs: k.strokeMs, slotTicks: slot).clamped(
            to: Self.bpmRange.lowerBound,
            Self.bpmRange.upperBound
        )
        notes = [KotekanHalf.polos, .sangsih].flatMap { half in
            let damp = k.damp(half)
            return k.pattern(half).enumerated().compactMap { i, key in
                key.map {
                    let set = damp.flatMap { $0.indices.contains(i) ? $0[i] : nil }
                    return DraftNote(
                        half: half,
                        key: $0,
                        tick: i * slot,
                        length: set.map { $0 * slot }
                    )
                }
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
    /// sensors can) — then the coarsest step every one lands on. Damp points
    /// are whole blocks, and a block is a whole number of slots, so they never
    /// make it finer.
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

    /// The damp points, slot by slot; nil when the half has none set, so a
    /// figure that keeps the default saves nothing extra.
    func dampGrid(_ half: KotekanHalf) -> [Int?]? {
        var grid = [Int?](repeating: nil, count: slotCount)
        for note in notes where note.half == half {
            if let length = note.length { grid[note.tick / slotTicks] = max(1, length / slotTicks) }
        }
        return grid.contains { $0 != nil } ? grid : nil
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
            colotomic: colotomic.map { ColotomicHit(slot: $0.tick / slotTicks, instrument: $0.instrument) },
            polosDamp: dampGrid(.polos),
            sangsihDamp: dampGrid(.sangsih)
        )
    }
}

private func gcd(_ a: Int, _ b: Int) -> Int {
    b == 0 ? a : gcd(b, a % b)
}

//
//  Kotekan.swift
//  gomelan
//
//  Kotekan are the interlocking figures at the heart of Balinese gangsa playing.
//  Two players share one composite melody: POLOS lands on the beat, SANGSIH
//  answers off the beat, and the two halves woven together make the line you
//  hear. This app teaches one half at a time.
//
//  A kotekan is stored as two 16-slot grids (`polos` / `sangsih`) over one gong
//  cycle. Each slot holds a KEY INDEX to strike, or nil for a rest — indices,
//  never pitches, so the same figure is portable across differently tuned
//  instruments (PRD §7). `makeSong` renders the chosen half over N cycles into
//  the note sequence the PlayEngine already knows how to run.
//

import Foundation

enum KotekanHalf: String, Equatable, Identifiable {
    case polos
    case sangsih

    var id: String { rawValue }
    var title: String { self == .polos ? "Polos" : "Sangsih" }
    /// The half your partner plays — the one the app takes over when you play alone.
    var other: KotekanHalf { self == .polos ? .sangsih : .polos }
    var eyebrow: String { self == .polos ? "On the beat" : "Off the beat" }
    var blurb: String {
        self == .polos
            ? "The straight half. You land on the pulse and hold the frame steady."
            : "The answering half. You fill the gaps polos leaves — harder, more fun."
    }
}

struct Kotekan: Identifiable, Equatable {
    var id: String
    var name: String            // "Kotekan Telu"
    var level: Int              // 1…3
    var toneLabel: String       // "3 tones", "4 tones", "Neighbour", "Sparse"
    var blurb: String           // one-line description for the selection card
    /// One gong cycle laid out as 16 grid slots. A value is the key index to
    /// strike on that slot; nil is a rest.
    var polos: [Int?]
    var sangsih: [Int?]
    /// Milliseconds per grid slot — sets the tempo (smaller = faster).
    var strokeMs: Int

    static let strokesPerCycle = 16

    /// Highest key index touched by either half, so we know the smallest
    /// instrument this figure fits on.
    var requiredKeys: Int {
        let maxIndex = (polos + sangsih).compactMap { $0 }.max() ?? 0
        return maxIndex + 1
    }

    func pattern(_ half: KotekanHalf) -> [Int?] {
        half == .polos ? polos : sangsih
    }

    /// The bilah this figure touches across BOTH halves — the lanes the river
    /// draws. Taken from the figure rather than from what is on screen, so the
    /// lanes stay put as the notes go by.
    var voicedKeyRange: ClosedRange<Int> {
        let used = (polos + sangsih).compactMap { $0 }
        guard let low = used.min(), let high = used.max() else { return 0...0 }
        return low...high
    }

    /// How many actual strokes a half plays in one cycle (rests excluded).
    func strokeCount(_ half: KotekanHalf) -> Int {
        pattern(half).compactMap { $0 }.count
    }

    var cycleMs: Int { Kotekan.strokesPerCycle * strokeMs }

    /// Render the chosen half, repeated `cycles` times, into engine notes.
    func makeSong(half: KotekanHalf, cycles: Int) -> Song {
        let grid = pattern(half)
        var notes: [Note] = []
        for c in 0..<cycles {
            for (slot, value) in grid.enumerated() {
                guard let key = value else { continue }
                let t = (c * Kotekan.strokesPerCycle + slot) * strokeMs
                notes.append(Note(keyIndex: key, timeMs: t, durationMs: Int(Double(strokeMs) * 0.9)))
            }
        }
        let duration = cycles * cycleMs
        // One "beat" per grid slot — keeps the metronome aligned to the pulse.
        let bpm = max(1, Int((60000.0 / Double(strokeMs)).rounded()))
        return Song(id: "\(id)-\(half.rawValue)",
                    title: name,
                    difficulty: .beginner,
                    bpm: bpm,
                    requiredKeys: requiredKeys,
                    durationMs: duration,
                    notes: notes)
    }
}

// MARK: - Bundled figures

extension Kotekan {
    /// The four figures offered in the picker, easiest first. Patterns interlock:
    /// polos fills the even slots, sangsih answers on the odd ones, so together
    /// they trace one continuous line.
    static let bundled: [Kotekan] = [
        Kotekan(
            id: "telu",
            name: "Kotekan Telu",
            level: 1,
            toneLabel: "3 tones",
            blurb: "The three-note weave every child in the banjar learns first.",
            polos:   [2, nil, 3, nil, 2, nil, 1, nil, 2, nil, 3, nil, 2, nil, 3, nil],
            sangsih: [nil, 3, nil, 2, nil, 3, nil, 2, nil, 1, nil, 2, nil, 3, nil, 2],
            strokeMs: 300
        ),
        Kotekan(
            id: "empat",
            name: "Kotekan Empat",
            level: 2,
            toneLabel: "4 tones",
            blurb: "Denser, four tones — the halves cross on every off-beat.",
            polos:   [1, nil, 2, nil, 3, nil, 4, nil, 3, nil, 2, nil, 1, nil, 2, nil],
            sangsih: [nil, 2, nil, 3, nil, 4, nil, 3, nil, 4, nil, 3, nil, 2, nil, 3],
            strokeMs: 260
        ),
        Kotekan(
            id: "norot",
            name: "Norot",
            level: 2,
            toneLabel: "Neighbour",
            blurb: "Each tone answered by the key beside it. Steady, hypnotic.",
            polos:   [3, nil, 3, nil, 3, nil, 3, nil, 2, nil, 2, nil, 4, nil, 4, nil],
            sangsih: [nil, 4, nil, 4, nil, 4, nil, 4, nil, 3, nil, 3, nil, 3, nil, 3],
            strokeMs: 300
        ),
        Kotekan(
            id: "nyokcok",
            name: "Nyok Cok",
            level: 3,
            toneLabel: "Sparse",
            blurb: "Wide gaps. Your ear has to hold the pulse alone.",
            polos:   [2, nil, nil, nil, 3, nil, nil, nil, 1, nil, nil, nil, 2, nil, nil, nil],
            sangsih: [nil, nil, 3, nil, nil, nil, 4, nil, nil, nil, 2, nil, nil, nil, 3, nil],
            strokeMs: 340
        ),
    ]
}

/// Instrument-style bilah label: keys read 1…n, and the top key of a two-octave
/// set echoes the low "1" an octave up, shown as "1·" (matches the design).
func bilahLabel(_ index: Int, count: Int) -> String {
    if count >= 6 && index == count - 1 { return "1·" }
    return "\(index + 1)"
}

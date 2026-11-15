//
//  Song.swift
//  Kotek
//
//  A song is a sequence of notes that reference a KEY INDEX, never a pitch or
//  note name (PRD §7). That is what makes patterns portable across differently
//  tuned instruments — the same pattern sounds correct in each instrument's own
//  tuning.
//

import Foundation

struct Note: Codable, Equatable, Identifiable {
    var keyIndex: Int
    var timeMs: Int
    /// How long the bilah rings before the hand stops it.
    var durationMs: Int
    /// Whether the hand stops it at the end of `durationMs`: false when the
    /// half's next stroke is this bilah again, which re-strikes it ringing.
    /// nil (a song not built from a kotekan) leaves it to `PlayEngine`, which
    /// works it out from the next note.
    var damped: Bool?

    var id: String {
        "\(keyIndex)-\(timeMs)"
    }
}

enum Difficulty: String, Codable, Equatable {
    case beginner
    case intermediate
    case advanced
}

struct Song: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var difficulty: Difficulty
    var bpm: Int
    var requiredKeys: Int
    var durationMs: Int
    var notes: [Note]
    /// Beats within one cycle that sound a kajar. nil for a song with none
    /// written; the engine no longer lays a kajar of its own under a figure.
    var kajarBeats: [Int]?
    /// The gong, kempur, klentong and kajar a player's figure carries — the
    /// cycle Studio laid under it — slot by slot. Played as written, instead
    /// of the engine's own gong and kempur. nil for a built-in, and for a
    /// figure saved with none, which keep the engine's.
    var colotomic: [ColotomicHit]?
}

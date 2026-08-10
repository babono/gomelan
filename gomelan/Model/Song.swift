//
//  Song.swift
//  gomelan
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
    var durationMs: Int

    var id: String { "\(keyIndex)-\(timeMs)" }
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
}

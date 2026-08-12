//
//  Judgement.swift
//  gomelan
//
//  The scoring model (PRD §5.1). Windows are deliberately generous — gamelan is
//  played at moderate tempi and beginners are slow, and the checker must err
//  generous rather than demotivate.
//

import Foundation
import SwiftUI

enum PlayMode: String, Equatable, Identifiable {
    case practice
    case play

    var id: String { rawValue }
    var title: String { self == .practice ? "Practice" : "Play" }
    var subtitle: String {
        self == .practice ? "No scoring, no fail — waits for you" : "Scored, timed"
    }
}

/// Judgement windows from §5.1. Starting values, tune during playtesting.
enum JudgementResult: String, Equatable {
    case perfect
    case good
    case lateEarly
    case miss
    case wrongKey

    var score: Int {
        switch self {
        case .perfect: return 100
        case .good: return 70
        case .lateEarly: return 30
        case .miss, .wrongKey: return 0
        }
    }

    var label: String {
        switch self {
        case .perfect: return "Perfect"
        case .good: return "Good"
        case .lateEarly: return "Late"
        case .miss: return "Miss"
        case .wrongKey: return "Wrong key"
        }
    }

    var color: Color {
        switch self {
        case .perfect: return Theme.hit
        case .good: return Theme.hit.opacity(0.8)
        case .lateEarly: return Theme.upcoming
        case .miss: return Theme.miss
        case .wrongKey: return Theme.wrong
        }
    }

    /// Correct key and reasonably on time — counts toward "on the beat".
    var onBeat: Bool { self == .perfect || self == .good }

    /// Classify a timing error (in ms) against generous practice/play windows.
    static func from(timingErrorMs: Double) -> JudgementResult {
        let e = abs(timingErrorMs)
        if e <= 200 { return .perfect }   // Generous Perfect (Green): 0..200ms
        if e <= 350 { return .good }      // Good / Buffer OK (Terracotta Orange): 200..350ms
        if e <= 500 { return .lateEarly } // Late/Early (Pale White): 350..500ms
        return .miss
    }
}

struct NoteJudgement: Identifiable, Equatable {
    let id = UUID()
    let keyIndex: Int
    let result: JudgementResult
    /// Signed timing error in ms; positive = struck early, negative = late.
    let timingErrorMs: Double
}

/// How one key fared across the run — drives the "where it slipped" list.
struct KeyBreakdown: Identifiable, Equatable {
    let keyIndex: Int
    let accuracy: Double   // 0…1
    let note: String       // short human description
    var id: Int { keyIndex }
}

struct SongResult: Equatable {
    let songTitle: String
    let subtitle: String
    let judgements: [NoteJudgement]

    var totalScore: Int { judgements.reduce(0) { $0 + $1.result.score } }
    var maxScore: Int { judgements.count * 100 }
    var accuracy: Double {
        guard maxScore > 0 else { return 0 }
        return Double(totalScore) / Double(maxScore)
    }

    var perfectCount: Int { judgements.filter { $0.result == .perfect }.count }
    var goodCount: Int { judgements.filter { $0.result == .good }.count }
    var missCount: Int { judgements.filter { $0.result == .miss || $0.result == .wrongKey }.count }

    /// Fraction of notes struck on the correct key and reasonably on time.
    var onBeatFraction: Double {
        guard !judgements.isEmpty else { return 0 }
        return Double(judgements.filter { $0.result.onBeat }.count) / Double(judgements.count)
    }

    /// Average signed timing error across the hits that landed (excludes misses,
    /// which have no meaningful time). Positive = ahead of the beat.
    var driftMs: Double {
        let hits = judgements.filter { $0.result != .miss && $0.result != .wrongKey }
        guard !hits.isEmpty else { return 0 }
        return hits.map(\.timingErrorMs).reduce(0, +) / Double(hits.count)
    }

    /// Per-key summary, worst first — "where it slipped".
    var breakdown: [KeyBreakdown] {
        let groups = Dictionary(grouping: judgements, by: \.keyIndex)
        return groups.map { key, notes -> KeyBreakdown in
            let acc = Double(notes.reduce(0) { $0 + $1.result.score }) / Double(notes.count * 100)
            let drift = notes.map(\.timingErrorMs).reduce(0, +) / Double(notes.count)
            let hasWrong = notes.contains { $0.result == .wrongKey }
            let note: String
            if acc >= 0.9 { note = "clean throughout" }
            else if hasWrong { note = "wrong key at times" }
            else if drift < -60 { note = "ran late" }
            else if drift > 60 { note = "ran early" }
            else { note = "uneven" }
            return KeyBreakdown(keyIndex: key, accuracy: acc, note: note)
        }
        .sorted { $0.accuracy > $1.accuracy }
    }
}

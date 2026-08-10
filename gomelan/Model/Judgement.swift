//
//  Judgement.swift
//  gomelan
//
//  The scoring model (PRD §5.1). Windows are deliberately generous — gamelan is
//  played at moderate tempi and beginners are slow.
//

import Foundation
import SwiftUI

enum PlayMode: String, Equatable, Identifiable {
    case practice
    case play

    var id: String { rawValue }
    var title: String { self == .practice ? "Practice" : "Play" }
    var subtitle: String {
        self == .practice ? "Gong, then the example, then you — looping" : "Gong, then the example, then one scored pass"
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

    /// Classify a timing error (in ms) against the §5.1 windows.
    static func from(timingErrorMs: Double) -> JudgementResult {
        let e = abs(timingErrorMs)
        if e <= 60 { return .perfect }
        if e <= 120 { return .good }
        if e <= 200 { return .lateEarly }
        return .miss
    }
}

struct NoteJudgement: Identifiable, Equatable {
    let id = UUID()
    let noteIndex: Int
    let result: JudgementResult
    let timingErrorMs: Double
}

struct SongResult: Equatable {
    let songTitle: String
    let judgements: [JudgementResult]

    var totalScore: Int { judgements.reduce(0) { $0 + $1.score } }
    var maxScore: Int { judgements.count * 100 }
    var accuracy: Double {
        guard maxScore > 0 else { return 0 }
        return Double(totalScore) / Double(maxScore)
    }

    var perfectCount: Int { judgements.filter { $0 == .perfect }.count }
    var goodCount: Int { judgements.filter { $0 == .good }.count }
    var missCount: Int { judgements.filter { $0 == .miss || $0 == .wrongKey }.count }
}

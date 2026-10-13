//
//  PracticeSessionRow.swift
//  Kotek
//

import Foundation

nonisolated struct PracticeSessionRow: Encodable {
    var userID: UUID
    var kotekanID: String?
    var instrumentID: UUID?
    var session: PracticeSession

    init(userID: UUID, kotekanID: String? = nil, instrumentID: UUID? = nil, session: PracticeSession) {
        self.userID = userID
        self.kotekanID = kotekanID
        self.instrumentID = instrumentID
        self.session = session
    }

    enum CodingKeys: String, CodingKey {
        case half, bpm, leniency, accuracy
        case userID = "user_id"
        case kotekanID = "kotekan_id"
        case instrumentID = "instrument_id"
        case tempoScale = "tempo_scale"
        case cycleCount = "cycle_count"
        case onTimeCount = "on_time_count"
        case wrongKeyCount = "wrong_key_count"
        case missedCount = "missed_count"
        case landedNotes = "landed_notes"
        case bestStreak = "best_streak"
        case driftMs = "drift_ms"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userID, forKey: .userID)
        try c.encodeIfPresent(kotekanID, forKey: .kotekanID)
        try c.encodeIfPresent(instrumentID, forKey: .instrumentID)
        try c.encode(session.half, forKey: .half)
        try c.encode(session.bpm, forKey: .bpm)
        try c.encode(session.tempoScale, forKey: .tempoScale)
        try c.encode(session.leniency, forKey: .leniency)
        try c.encode(session.cycleCount, forKey: .cycleCount)
        try c.encodeIfPresent(session.accuracy, forKey: .accuracy)
        try c.encode(session.onTimeCount, forKey: .onTimeCount)
        try c.encode(session.wrongKeyCount, forKey: .wrongKeyCount)
        try c.encode(session.missedCount, forKey: .missedCount)
        try c.encode(session.landedNotes, forKey: .landedNotes)
        try c.encode(session.bestStreak, forKey: .bestStreak)
        try c.encodeIfPresent(session.driftMs, forKey: .driftMs)
    }
}

/// A filed session as the history screen reads it back. Only the columns it
/// shows; `created_at` is filled in by the database.
nonisolated struct PracticeHistoryRow: Decodable, Identifiable {
    var id: String {
        createdAt
    }

    var kotekanID: String?
    var half: String
    var tempoScale: Double
    var accuracy: Double?
    var landedNotes: Int
    var bestStreak: Int
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case half, accuracy
        case kotekanID = "kotekan_id"
        case tempoScale = "tempo_scale"
        case landedNotes = "landed_notes"
        case bestStreak = "best_streak"
        case createdAt = "created_at"
    }
}

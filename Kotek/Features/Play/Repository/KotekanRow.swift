//
//  KotekanRow.swift
//  Kotek
//

import Foundation

nonisolated struct KotekanRow: Codable {
    var id: String
    var userID: UUID?
    var instrumentID: UUID?
    var name: String
    var description: String?
    var level: Int?
    var slotsPerCycle: Int
    var bpm: Int
    var source: KotekanSource

    init(
        id: String,
        userID: UUID? = nil,
        instrumentID: UUID? = nil,
        name: String,
        description: String? = nil,
        level: Int? = nil,
        slotsPerCycle: Int,
        bpm: Int,
        source: KotekanSource
    ) {
        self.id = id
        self.userID = userID
        self.instrumentID = instrumentID
        self.name = name
        self.description = description
        self.level = level
        self.slotsPerCycle = slotsPerCycle
        self.bpm = bpm
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, level, bpm, source
        case userID = "user_id"
        case instrumentID = "instrument_id"
        case slotsPerCycle = "slots_per_cycle"
    }
}

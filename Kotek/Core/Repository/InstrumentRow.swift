//
//  InstrumentRow.swift
//  Kotek
//

import Foundation

nonisolated struct InstrumentRow: Codable, Sendable {
    var id: UUID
    var userID: UUID
    var name: String
    var type: String
    var keyCount: Int
    var createdAt: String

    init(id: UUID, userID: UUID, name: String, type: String, keyCount: Int, createdAt: String) {
        self.id = id
        self.userID = userID
        self.name = name
        self.type = type
        self.keyCount = keyCount
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type
        case userID = "user_id"
        case keyCount = "key_count"
        case createdAt = "created_at"
    }
}

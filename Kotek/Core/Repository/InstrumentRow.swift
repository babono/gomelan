//
//  InstrumentRow.swift
//  Kotek
//

import Foundation

nonisolated struct InstrumentRow: Codable {
    var id: UUID
    var userID: UUID
    var name: String
    var type: String
    var keyCount: Int
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, type
        case userID = "user_id"
        case keyCount = "key_count"
        case createdAt = "created_at"
    }
}

//
//  InstrumentRow.swift
//  Kotek
//

import Foundation
import Supabase

nonisolated struct InstrumentRow: Codable {
    var id: UUID
    var userID: UUID
    var name: String
    var type: String
    var keyCount: Int
    var createdAt: String
    /// The whole profile, as `ProfileStore` writes it. The columns above stay
    /// for querying; this is what a second phone restores from. Nil on rows
    /// uploaded before it existed.
    var profile: AnyJSON?

    enum CodingKeys: String, CodingKey {
        case id, name, type, profile
        case userID = "user_id"
        case keyCount = "key_count"
        case createdAt = "created_at"
    }
}

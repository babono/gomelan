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
    /// The strike controller (§7). Columns, not part of `profile`: the
    /// controller is shared between gangsa, so it is a row of its own.
    var controllerID: UUID?
    var controllerInputs: [Int]?
    var controllerSetUpAt: String?
    /// Read only — embedded by `select("*, controllers(*)")`.
    var controller: ControllerRow?

    enum CodingKeys: String, CodingKey {
        case id, name, type, profile
        case userID = "user_id"
        case keyCount = "key_count"
        case createdAt = "created_at"
        case controllerID = "controller_id"
        case controllerInputs = "controller_inputs"
        case controllerSetUpAt = "controller_set_up_at"
        case controller = "controllers"
    }

    /// R Written by hand so the controller columns go up as explicit nulls:
    /// R synthesized encoding OMITS a nil, and "Forget controller" has to clear
    /// R them on the server, not leave the old link standing.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(name, forKey: .name)
        try c.encode(type, forKey: .type)
        try c.encode(keyCount, forKey: .keyCount)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(profile, forKey: .profile)
        try c.encode(controllerID, forKey: .controllerID)
        try c.encode(controllerInputs, forKey: .controllerInputs)
        try c.encode(controllerSetUpAt, forKey: .controllerSetUpAt)
    }
}

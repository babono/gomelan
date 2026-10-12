//
//  ControllerRow.swift
//  Kotek
//

import Foundation

/// One strike controller the player owns (PRD §7). Shared between gangsa, so it
/// is its own row rather than columns on any one instrument.
nonisolated struct ControllerRow: Codable {
    /// Nil on the way up: the row is upserted on (user_id, hardware_id), and
    /// sending an id would try to rewrite the primary key of a row other
    /// gangsa already point at.
    var id: UUID?
    var userID: UUID?
    var hardwareID: String
    var name: String
    var inputCount: Int
    var hasPlugDetect: Bool
    var firmwareVersion: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case userID = "user_id"
        case hardwareID = "hardware_id"
        case inputCount = "input_count"
        case hasPlugDetect = "has_plug_detect"
        case firmwareVersion = "firmware_version"
    }
}

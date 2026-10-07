//
//  KotekanHitRow.swift
//  Kotek
//

import Foundation

nonisolated struct KotekanHitRow: Codable {
    var kotekanID: String
    /// `hit_type`: polos | sangsih | gong | kempur | kajar.
    var type: String
    var beatIndex: Int
    var keyIndex: Int?

    init(kotekanID: String, type: String, beatIndex: Int, keyIndex: Int? = nil) {
        self.kotekanID = kotekanID
        self.type = type
        self.beatIndex = beatIndex
        self.keyIndex = keyIndex
    }

    enum CodingKeys: String, CodingKey {
        case type
        case kotekanID = "kotekan_id"
        case beatIndex = "beat_index"
        case keyIndex = "key_index"
    }
}

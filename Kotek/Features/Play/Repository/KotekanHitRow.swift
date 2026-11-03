//
//  KotekanHitRow.swift
//  Kotek
//

import Foundation

nonisolated struct KotekanHitRow: Codable {
    var kotekanID: String
    /// `hit_type`: polos | sangsih | gong | kempur | klentong | kajar.
    var type: String
    var beatIndex: Int
    var keyIndex: Int?
    /// `damp_slots`: on a polos or sangsih stroke, the slots it rings before
    /// the hand damps it. NULL is the default — until the half's next stroke.
    /// Left out of the request when nil, so saving a figure without damp
    /// points works whether or not the column exists yet.
    var dampSlots: Int?

    init(kotekanID: String, type: String, beatIndex: Int, keyIndex: Int? = nil, dampSlots: Int? = nil) {
        self.kotekanID = kotekanID
        self.type = type
        self.beatIndex = beatIndex
        self.keyIndex = keyIndex
        self.dampSlots = dampSlots
    }

    enum CodingKeys: String, CodingKey {
        case type
        case kotekanID = "kotekan_id"
        case beatIndex = "beat_index"
        case keyIndex = "key_index"
        case dampSlots = "damp_slots"
    }
}

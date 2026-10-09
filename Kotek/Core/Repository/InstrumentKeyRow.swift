//
//  InstrumentKeyRow.swift
//  Kotek
//

import Foundation

/// Only the columns the app owns. `sensor_id`, `sensor_threshold` and
/// `sample_path` are left out of the payload entirely, so an upsert from here
/// never overwrites what the sensor setup writes into them.
nonisolated struct InstrumentKeyRow: Encodable {
    var instrumentID: UUID
    var keyIndex: Int
    var baseHz: Float?

    init(instrumentID: UUID, keyIndex: Int, baseHz: Float? = nil) {
        self.instrumentID = instrumentID
        self.keyIndex = keyIndex
        self.baseHz = baseHz
    }

    enum CodingKeys: String, CodingKey {
        case instrumentID = "instrument_id"
        case keyIndex = "key_index"
        case baseHz = "base_hz"
    }

    /// R Written by hand to send an explicit null. Synthesized encoding OMITS a
    /// R nil, and PostgREST refuses a bulk upsert whose rows disagree on keys —
    /// R so one uncalibrated key would sink the whole instrument's write.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(instrumentID, forKey: .instrumentID)
        try c.encode(keyIndex, forKey: .keyIndex)
        try c.encode(baseHz, forKey: .baseHz)
    }
}

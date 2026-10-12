//
//  InstrumentKeyRow.swift
//  Kotek
//

import Foundation

/// Only the columns the app owns. `sensor_id` (the hand-made column the
/// controller setup does not use — see the controllers migration),
/// `sensor_threshold` and `sample_path` are left out of the payload entirely.
nonisolated struct InstrumentKeyRow: Encodable {
    var instrumentID: UUID
    var keyIndex: Int
    var baseHz: Float?
    /// The controller input whose sensor sits on this bilah (§3.6.5).
    var sensorInput: Int?

    init(instrumentID: UUID, keyIndex: Int, baseHz: Float? = nil, sensorInput: Int? = nil) {
        self.instrumentID = instrumentID
        self.keyIndex = keyIndex
        self.baseHz = baseHz
        self.sensorInput = sensorInput
    }

    enum CodingKeys: String, CodingKey {
        case instrumentID = "instrument_id"
        case keyIndex = "key_index"
        case baseHz = "base_hz"
        case sensorInput = "sensor_input"
    }

    /// R Written by hand to send an explicit null. Synthesized encoding OMITS a
    /// R nil, and PostgREST refuses a bulk upsert whose rows disagree on keys —
    /// R so one uncalibrated key would sink the whole instrument's write.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(instrumentID, forKey: .instrumentID)
        try c.encode(keyIndex, forKey: .keyIndex)
        try c.encode(baseHz, forKey: .baseHz)
        try c.encode(sensorInput, forKey: .sensorInput)
    }
}

/// The per-key controller map, read back for restoring on another phone.
nonisolated struct InstrumentKeySensorRow: Decodable {
    var instrumentID: UUID
    var keyIndex: Int
    var sensorInput: Int?

    enum CodingKeys: String, CodingKey {
        case instrumentID = "instrument_id"
        case keyIndex = "key_index"
        case sensorInput = "sensor_input"
    }
}

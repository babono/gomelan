//
//  CalibrationFile.swift
//  Kotek
//
//  Reads `calibration.json` exactly as `build_calibration.py` writes it, so a
//  profile tuned in the Python notebook can be dropped into the app unchanged.
//
//  The file carries its own config block. Use it rather than the app defaults —
//  the Python builder deliberately overrides some library defaults for real
//  recordings (200-8000Hz, noise subtraction 3.0), and a fingerprint compared
//  against a template built with different settings is meaningless.
//

import Foundation

struct CalibrationFile: Decodable {

    struct Key: Decodable {
        let name: String
        let vector: [Float]
    }

    struct StoredConfig: Decodable {
        let sr: Int
        let onsetWindow: Int
        let onsetHop: Int
        let fluxFloorHz: Double
        let medianLengthSeconds: Double
        let threshMultiplier: Float
        let threshFloor: Float
        let minGapSeconds: Double
        let fpWindow: Int
        let fpDelaySeconds: Double
        let fpLoHz: Double
        let fpHiHz: Double
        let fpBands: Int
        let fpCompress: Float
        let fpNoiseSub: Float?
        let fpNoiseLeadSeconds: Double?
        let confidenceGap: Float

        enum CodingKeys: String, CodingKey {
            case sr
            case onsetWindow = "onset_win"
            case onsetHop = "onset_hop"
            case fluxFloorHz = "flux_floor_hz"
            case medianLengthSeconds = "median_len_s"
            case threshMultiplier = "thresh_mult"
            case threshFloor = "thresh_floor"
            case minGapSeconds = "min_gap_s"
            case fpWindow = "fp_win"
            case fpDelaySeconds = "fp_delay_s"
            case fpLoHz = "fp_lo_hz"
            case fpHiHz = "fp_hi_hz"
            case fpBands = "fp_bands"
            case fpCompress = "fp_compress"
            case fpNoiseSub = "fp_noise_sub"
            case fpNoiseLeadSeconds = "fp_noise_lead_s"
            case confidenceGap = "confidence_gap"
        }
    }

    let config: StoredConfig
    let keys: [Key]

    /// Rebuild a DSPConfig from the file.
    ///
    /// `sampleRate` deliberately comes from the running device, NOT from the
    /// file. The fingerprint bands are defined in Hz, so templates survive a
    /// sample-rate change as long as the band table is rebuilt at the rate
    /// actually in use. Copying 44100 in here when the mic runs at 48000 would
    /// put every band edge in the wrong place.
    func dspConfig(sampleRate: Double) -> DSPConfig {
        var c = DSPConfig()
        c.sampleRate = sampleRate
        c.onsetWindow = config.onsetWindow
        c.onsetHop = config.onsetHop
        c.fluxFloorHz = config.fluxFloorHz
        c.medianLengthSeconds = config.medianLengthSeconds
        c.threshMultiplier = config.threshMultiplier
        c.threshFloor = config.threshFloor
        c.minGapSeconds = config.minGapSeconds
        c.fpWindow = config.fpWindow
        c.fpDelaySeconds = config.fpDelaySeconds
        c.fpLoHz = config.fpLoHz
        c.fpHiHz = config.fpHiHz
        c.fpBands = config.fpBands
        c.fpCompress = config.fpCompress
        c.fpNoiseSub = config.fpNoiseSub ?? 0
        c.fpNoiseLeadSeconds = config.fpNoiseLeadSeconds ?? 0.010
        c.confidenceGap = config.confidenceGap
        return c
    }

    static func load(from url: URL) throws -> CalibrationFile {
        try JSONDecoder().decode(CalibrationFile.self, from: Data(contentsOf: url))
    }

    /// Loads `calibration.json` from the app bundle, if present.
    static func loadFromBundle(named name: String = "calibration") -> CalibrationFile? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else { return nil }
        return try? load(from: url)
    }

    /// Templates in file order, keyed by position, ready for an InstrumentProfile.
    /// Names are preserved so the UI can show "ding" rather than "key 0".
    var templates: [(index: Int, name: String, vector: [Float])] {
        keys.enumerated().map { (index: $0.offset, name: $0.element.name, vector: $0.element.vector) }
    }
}

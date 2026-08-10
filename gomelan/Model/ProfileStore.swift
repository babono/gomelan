//
//  ProfileStore.swift
//  gomelan
//
//  Persists the calibrated instrument profile to Documents so pitches recorded
//  on the real instrument (and alignment tweaks) survive relaunch. Uses the
//  same snake_case JSON shape as the PRD §7 / bundled profile, so a saved file
//  can be lifted straight into the app bundle as the shipped default.
//

import Foundation

enum ProfileStore {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("instrument_profile.json")
    }

    static func load() -> InstrumentProfile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(InstrumentProfile.self, from: data)
    }

    static func save(_ profile: InstrumentProfile) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(profile) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Discard the saved profile and fall back to the bundled default.
    static func reset() {
        try? FileManager.default.removeItem(at: url)
    }
}

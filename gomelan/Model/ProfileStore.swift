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
    private static var listUrl: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("instruments_store.json")
    }

    private static var legacyUrl: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("instrument_profile.json")
    }

    private static let selectedKey = "gomelan_selected_instrument_id"

    /// Load all saved instrument profiles.
    static func loadAll() -> [InstrumentProfile] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // Try reading multi-profile store
        if let data = try? Data(contentsOf: listUrl),
           let profiles = try? decoder.decode([InstrumentProfile].self, from: data),
           !profiles.isEmpty {
            return profiles
        }

        // Migrate legacy single-profile file if present
        if let legacyData = try? Data(contentsOf: legacyUrl),
           let single = try? decoder.decode(InstrumentProfile.self, from: legacyData) {
            let migrated = [single]
            saveAll(migrated)
            return migrated
        }

        return []
    }

    /// Save the complete list of instrument profiles to Documents.
    static func saveAll(_ profiles: [InstrumentProfile]) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(profiles) else { return }
        try? data.write(to: listUrl, options: .atomic)
    }

    /// Insert or update a single profile by matching ID.
    static func save(_ profile: InstrumentProfile) {
        var all = loadAll()
        if let idx = all.firstIndex(where: { $0.id == profile.id }) {
            all[idx] = profile
        } else {
            all.append(profile)
        }
        saveAll(all)
        setSelectedID(profile.id)
    }

    /// Delete a profile by ID.
    static func delete(_ id: String) {
        var all = loadAll()
        all.removeAll { $0.id == id }
        saveAll(all)
        if getSelectedID() == id {
            setSelectedID(all.first?.id ?? "")
        }
    }

    /// ID of the currently selected instrument.
    static func getSelectedID() -> String? {
        UserDefaults.standard.string(forKey: selectedKey)
    }

    static func setSelectedID(_ id: String) {
        UserDefaults.standard.set(id, forKey: selectedKey)
    }

    /// Load the active selected instrument profile.
    static func loadSelected() -> InstrumentProfile? {
        let all = loadAll()
        if let selectedID = getSelectedID(), let match = all.first(where: { $0.id == selectedID }) {
            return match
        }
        return all.first
    }

    /// Legacy single-profile fallback helper.
    static func load() -> InstrumentProfile? {
        loadSelected()
    }

    /// Discard all saved profiles.
    static func reset() {
        try? FileManager.default.removeItem(at: listUrl)
        try? FileManager.default.removeItem(at: legacyUrl)
        UserDefaults.standard.removeObject(forKey: selectedKey)
    }
}

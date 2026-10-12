//
//  KotekanStore.swift
//  Kotek
//
//  The last catalogue Supabase sent, kept in Documents. Without it a player's
//  own patterns only existed on the server: opening the app offline showed the
//  built-ins alone, and even online they popped into the rail a beat after it
//  appeared, once the fetch came back.
//

import Foundation

enum KotekanStore {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kotekan_catalogue.json")
    }

    /// Nil when there is no copy yet — a first launch, or just signed out.
    static func load() -> [Kotekan]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Kotekan].self, from: data)
    }

    // ponytail: written on the main actor. A catalogue is a few kilobytes and
    // changes only on a fetch, a save or a delete.
    static func save(_ kotekans: [Kotekan]) {
        guard let data = try? JSONEncoder().encode(kotekans) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func reset() {
        try? FileManager.default.removeItem(at: url)
    }
}

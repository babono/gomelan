//
//  KotekanRepository.swift
//  Kotek
//
//  Repository handling Kotekan catalogue fetching and user figure saving.
//  Scoped to the Play feature where figures are chosen and played.
//

import Foundation
import OSLog

nonisolated struct KotekanRepository {
    private let remote: SupabaseRepository
    private let log = Logger(subsystem: "Kotek", category: "kotekan-repo")

    init(remote: SupabaseRepository = SupabaseRepository()) {
        self.remote = remote
    }

    /// The built-in catalogue plus this user's own figures, as plain grids.
    /// `Kotekan(remote:)` turns them into figures on the main actor, where the
    /// model lives.
    func catalogue() async throws -> [RemoteKotekan] {
        do {
            _ = try await remote.userID()
        } catch {
            log.error("sign-in failed, reading built-ins only: \(error.localizedDescription)")
        }

        let rows: [KotekanRow] = try await remote.read(from: "kotekan")
        guard !rows.isEmpty else { return [] }

        let hits: [KotekanHitRow] = try await remote.read(
            from: "kotekan_hits",
            matching: "kotekan_id",
            in: rows.map(\.id)
        )

        let hitsByID = Dictionary(grouping: hits, by: \.kotekanID)
        return rows.compactMap { RemoteKotekan(row: $0, hits: hitsByID[$0.id] ?? []) }
    }

    /// A kotekan the player made — from the Create Kotek flow, tapped in by
    /// hand (`.manual`) or recorded off the sensors (`.automatic`).
    func saveKotekan(_ k: RemoteKotekan) async throws {
        let uid = try await remote.userID()
        let row = KotekanRow(
            id: k.id,
            userID: uid,
            instrumentID: k.instrumentID.flatMap(UUID.init(uuidString:)),
            name: k.name,
            description: k.description,
            level: k.level,
            slotsPerCycle: k.polos.count,
            bpm: k.bpm,
            source: k.source
        )
        try await remote.upsert(row, in: "kotekan")

        try await remote.delete(from: "kotekan_hits", matching: "kotekan_id", equals: k.id)
        let hits = [("polos", k.polos), ("sangsih", k.sangsih)].flatMap { type, grid in
            grid.enumerated().compactMap { slot, key in
                key.map { KotekanHitRow(kotekanID: k.id, type: type, beatIndex: slot, keyIndex: $0) }
            }
        }
        if !hits.isEmpty {
            try await remote.create(hits, in: "kotekan_hits")
        }
    }
}

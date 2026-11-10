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
        let halves = [("polos", k.polos, k.polosDamp), ("sangsih", k.sangsih, k.sangsihDamp)]
        let hits = halves.flatMap { type, grid, damp in
            grid.enumerated().compactMap { slot, key in
                key.map {
                    KotekanHitRow(
                        kotekanID: k.id,
                        type: type,
                        beatIndex: slot,
                        keyIndex: $0,
                        dampSlots: damp.flatMap { $0.indices.contains(slot) ? $0[slot] : nil }
                    )
                }
            }
        } + k.colotomic.map {
            KotekanHitRow(kotekanID: k.id, type: $0.instrument.hitType, beatIndex: $0.slot)
        }
        if !hits.isEmpty {
            try await remote.create(hits, in: "kotekan_hits")
        }
    }

    // MARK: - Sharing

    /// The functions' arguments, by name. `instrumentID` nil goes as NULL.
    private nonisolated struct ShareParams: Encodable {
        let id: String
        var instrumentID: UUID??

        enum CodingKeys: String, CodingKey {
            case id = "p_id"
            case instrumentID = "p_instrument_id"
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            // Present only for the copy, and then always — NULL included, or
            // PostgREST looks for a one-argument function that is not there.
            if let instrumentID { try c.encode(instrumentID, forKey: .instrumentID) }
        }
    }

    /// `shared_kotekan_figure`'s one object: the row's columns with its hits.
    private nonisolated struct SharedFigure: Decodable {
        let row: KotekanRow
        let hits: [KotekanHitRow]

        enum CodingKeys: String, CodingKey { case hits }

        init(from decoder: any Decoder) throws {
            row = try KotekanRow(from: decoder)
            hits = try decoder.container(keyedBy: CodingKeys.self).decode([KotekanHitRow].self, forKey: .hits)
        }
    }

    /// A shared figure, whole, read past row-level security by
    /// `shared_kotekan_figure` — the add screen draws its notes, as the
    /// picker's cards do. Nil when it is gone, or was never a player's.
    func shared(id: String) async throws -> RemoteKotekan? {
        let figure: SharedFigure? = try await remote.call("shared_kotekan_figure", params: ShareParams(id: id))
        return figure.flatMap { RemoteKotekan(row: $0.row, hits: $0.hits) }
    }

    /// A copy of someone's figure, now this player's own, filed on the gangsa
    /// given. Not synced with the original — see the share migration. Returns
    /// the copy's id.
    func copyShared(id: String, instrumentID: String?) async throws -> String {
        try await remote.call(
            "copy_shared_kotekan",
            params: ShareParams(id: id, instrumentID: .some(instrumentID.flatMap(UUID.init(uuidString:))))
        )
    }

    /// A player's own figure, gone: its hits, then the row. Row-level security
    /// limits both deletes to rows this user owns, so a built-in cannot be
    /// removed from here even by mistake.
    func deleteKotekan(id: String) async throws {
        try await remote.delete(from: "kotekan_hits", matching: "kotekan_id", equals: id)
        try await remote.delete(from: "kotekan", matching: "id", equals: id)
    }
}

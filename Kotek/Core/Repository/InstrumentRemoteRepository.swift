//
//  InstrumentRemoteRepository.swift
//  Kotek
//
//  Remote repository managing Supabase persistence for instrument profiles
//  and bilah tuning keys. Used by AppState, Settings, and practice session recording.
//

import Foundation

nonisolated struct InstrumentRemoteRepository: Sendable {
    private let remote: SupabaseRepository

    init(remote: SupabaseRepository = SupabaseRepository()) {
        self.remote = remote
    }

    func saveInstrument(_ p: InstrumentProfile) async throws {
        //R Only instruments with a UUID id go up. The bundled default
        //R ("gangsa-exhibition-unit") is a placeholder, not something the
        //R player set up, and the column would reject its id anyway.
        guard let id = UUID(uuidString: p.id) else { return }
        let uid = try await remote.userID()

        let row = await InstrumentRow(
            id: id,
            userID: uid,
            name: p.name,
            type: p.type.rawValue,
            keyCount: p.keyCount,
            createdAt: p.createdAt
        )
        try await remote.upsert(row, in: "instruments")

        let keys = p.keys.map {
            InstrumentKeyRow(
                instrumentID: id,
                keyIndex: $0.index,
                baseHz: $0.fundamentalHz > 0 ? Float($0.fundamentalHz) : nil
            )
        }
        if !keys.isEmpty {
            try await remote.upsert(keys, in: "instrument_keys")
        }

        //R Keys past the count are left over from a resize down. Deleted rather
        //R than kept: index addresses the bilah, and a row for bilah 12 on a
        //R ten-key gangsa is a key that does not exist.
        try await remote.delete(
            from: "instrument_keys",
            matching: "instrument_id",
            equals: id,
            andColumn: "key_index",
            gte: p.keyCount
        )
    }

    func deleteInstrument(id: String) async throws {
        guard let id = UUID(uuidString: id) else { return }
        _ = try await remote.userID()
        //R Keys first: their policy looks the instrument up, so once it is gone
        //R they can no longer be reached to delete.
        try await remote.delete(from: "instrument_keys", matching: "instrument_id", equals: id)
        try await remote.delete(from: "instruments", matching: "id", equals: id)
    }
}

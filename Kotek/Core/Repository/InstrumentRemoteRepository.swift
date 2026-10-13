//
//  InstrumentRemoteRepository.swift
//  Kotek
//
//  Remote repository managing Supabase persistence for instrument profiles
//  and bilah tuning keys. Used by AppState, Settings, and practice session recording.
//

import Foundation
import Supabase

nonisolated struct InstrumentRemoteRepository {
    private let remote: SupabaseRepository

    init(remote: SupabaseRepository = SupabaseRepository()) {
        self.remote = remote
    }

    func saveInstrument(_ p: InstrumentProfile) async throws {
        // R Only instruments with a UUID id go up. The bundled default
        // R ("gangsa-exhibition-unit") is a placeholder, not something the
        // R player set up, and the column would reject its id anyway.
        guard let id = UUID(uuidString: p.id) else { return }
        let uid = try await remote.userID()

        // The controller row first: the instrument points at it.
        var controllerID: UUID?
        if let link = p.controller {
            let saved: ControllerRow = try await remote.upsert(
                ControllerRow(
                    userID: uid,
                    hardwareID: link.hardwareId,
                    name: link.name,
                    inputCount: link.inputCount,
                    hasPlugDetect: link.hasPlugDetect,
                    firmwareVersion: link.firmware
                ),
                in: "controllers",
                onConflict: "user_id,hardware_id"
            )
            controllerID = saved.id
        }

        let row = InstrumentRow(
            id: id,
            userID: uid,
            name: p.name,
            type: p.type.rawValue,
            keyCount: p.keyCount,
            createdAt: p.createdAt,
            profile: try JSONDecoder().decode(AnyJSON.self, from: ProfileStore.encoded(Self.withoutController(p))),
            controllerID: controllerID,
            controllerInputs: p.controller?.inputs,
            controllerSetUpAt: p.controller?.setUpAt
        )
        try await remote.upsert(row, in: "instruments")

        let keys = p.keys.map {
            InstrumentKeyRow(
                instrumentID: id,
                keyIndex: $0.index,
                baseHz: $0.fundamentalHz > 0 ? Float($0.fundamentalHz) : nil,
                sensorInput: p.controller == nil ? nil : $0.sensorInput
            )
        }
        if !keys.isEmpty {
            try await remote.upsert(keys, in: "instrument_keys")
        }

        // R Keys past the count are left over from a resize down. Deleted rather
        // R than kept: index addresses the bilah, and a row for bilah 12 on a
        // R ten-key gangsa is a key that does not exist.
        try await remote.delete(
            from: "instrument_keys",
            matching: "instrument_id",
            equals: id,
            andColumn: "key_index",
            gte: p.keyCount
        )
    }

    /// Every instrument this account has uploaded. `profile` is nil for a row
    /// from before the column existed: it is there, but cannot be restored.
    func fetchInstruments() async throws -> [(id: String, profile: InstrumentProfile?)] {
        let uid = try await remote.userID()
        let rows: [InstrumentRow] = try await remote.read(
            from: "instruments",
            columns: "*, controllers(*)",
            matching: "user_id",
            equals: uid
        )
        let sensorKeys: [InstrumentKeySensorRow] = try await remote.read(
            from: "instrument_keys",
            matching: "instrument_id",
            in: rows.filter { $0.controller != nil }.map(\.id)
        )
        let inputs = Dictionary(grouping: sensorKeys, by: \.instrumentID)
        return rows.map { row in
            let profile = row.profile.flatMap { json in
                try? ProfileStore.decoded(InstrumentProfile.self, from: JSONEncoder().encode(json))
            }.map { Self.withController(of: row, keys: inputs[row.id] ?? [], on: $0) }
            // Uppercase, as `UUID().uuidString` made it on the phone; the
            // column hands it back lowercase.
            return (row.id.uuidString, profile)
        }
    }

    /// The `profile` JSON goes up without the controller: the columns and the
    /// `controllers` table are its record, and a second copy inside the blob
    /// would only be something for the two to disagree about.
    private static func withoutController(_ p: InstrumentProfile) -> InstrumentProfile {
        var stripped = p
        stripped.controller = nil
        for i in stripped.keys.indices { stripped.keys[i].sensorInput = nil }
        return stripped
    }

    /// And comes back with it, from the columns.
    private static func withController(
        of row: InstrumentRow,
        keys: [InstrumentKeySensorRow],
        on p: InstrumentProfile
    ) -> InstrumentProfile {
        var restored = p
        if let c = row.controller {
            restored.controller = ControllerLink(
                hardwareId: c.hardwareID,
                name: c.name,
                inputCount: c.inputCount,
                hasPlugDetect: c.hasPlugDetect,
                firmware: c.firmwareVersion,
                inputs: row.controllerInputs,
                setUpAt: row.controllerSetUpAt ?? row.createdAt
            )
        } else {
            restored.controller = nil
        }
        let byKey = Dictionary(keys.map { ($0.keyIndex, $0.sensorInput) }) { a, _ in a }
        for i in restored.keys.indices {
            restored.keys[i].sensorInput = restored.controller == nil ? nil : byKey[restored.keys[i].index] ?? nil
        }
        return restored
    }

    func deleteInstrument(id: String) async throws {
        guard let id = UUID(uuidString: id) else { return }
        _ = try await remote.userID()
        // R Keys first: their policy looks the instrument up, so once it is gone
        // R they can no longer be reached to delete.
        try await remote.delete(from: "instrument_keys", matching: "instrument_id", equals: id)
        try await remote.delete(from: "instruments", matching: "id", equals: id)
    }

    // MARK: - Photos

    /// Private bucket; its policy lets a user reach only the folder named for
    /// their own id (supabase/migrations/20261013020000_instrument_photos.sql).
    private static let photoBucket = "instrument-photos"

    /// `<user id>/<instrument id>-<version>.jpg`. The version in the name means
    /// a phone fetching a photo the profile says is current can never get an
    /// older one that happened to be under the same path.
    private func photoPath(id: String, version: String) async throws -> String {
        let uid = try await remote.userID()
        return "\(uid.uuidString.lowercased())/\(InstrumentPhotoStore.fileName(id: id, version: version))"
    }

    func uploadPhoto(_ jpeg: Data, id: String, version: String) async throws {
        try await remote.client.storage.from(Self.photoBucket).upload(
            try await photoPath(id: id, version: version),
            data: jpeg,
            options: FileOptions(contentType: "image/jpeg", upsert: true)
        )
    }

    func downloadPhoto(id: String, version: String) async throws -> Data {
        try await remote.client.storage.from(Self.photoBucket)
            .download(path: try await photoPath(id: id, version: version))
    }

    func deletePhoto(id: String, version: String) async throws {
        _ = try await remote.client.storage.from(Self.photoBucket)
            .remove(paths: [try await photoPath(id: id, version: version)])
    }
}

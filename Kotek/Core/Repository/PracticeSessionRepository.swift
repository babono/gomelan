//
//  PracticeSessionRepository.swift
//  Kotek
//
//  Repository handling practice session records: filed by the Play feature
//  when a session ends, read back by the history screen in Settings.
//

import Foundation

nonisolated struct PracticeSessionRepository {
    private let remote: SupabaseRepository
    private let instrumentRepository: InstrumentRemoteRepository

    init(
        remote: SupabaseRepository = SupabaseRepository(),
        instrumentRepository: InstrumentRemoteRepository = InstrumentRemoteRepository()
    ) {
        self.remote = remote
        self.instrumentRepository = instrumentRepository
    }

    /// File a finished session. The instrument goes up first, in the same call,
    /// because the insert policy checks the player owns it.
    func recordSession(_ s: PracticeSession, on instrument: InstrumentProfile) async throws {
        try await instrumentRepository.saveInstrument(instrument)
        let uid = try await remote.userID()

        var validKotekanID: String? = nil
        if let kid = s.kotekanID {
            let matches: [KotekanRow] = await (try? remote.read(from: "kotekan", matching: "id", equals: kid)) ?? []
            if !matches.isEmpty {
                validKotekanID = kid
            }
        }

        let row = PracticeSessionRow(
            userID: uid,
            kotekanID: validKotekanID,
            instrumentID: UUID(uuidString: instrument.id),
            session: s
        )
        try await remote.create(row, in: "practice_session")
    }

    /// The most recent sessions played on one instrument, newest first.
    func history(instrumentID: String, limit: Int = 50) async throws -> [PracticeHistoryRow] {
        guard let id = UUID(uuidString: instrumentID) else { return [] }
        _ = try await remote.userID()
        return try await remote.read(
            from: "practice_session",
            matching: "instrument_id",
            equals: id,
            newestFirstBy: "created_at",
            limit: limit
        )
    }
}

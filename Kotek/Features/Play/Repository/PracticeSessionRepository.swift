//
//  PracticeSessionRepository.swift
//  Kotek
//
//  Repository handling practice session record persistence.
//  Scoped to the Play feature where sessions are executed and scored.
//

import Foundation

nonisolated struct PracticeSessionRepository: Sendable {
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
            let matches: [KotekanRow] = (try? await remote.read(from: "kotekan", matching: "id", equals: kid)) ?? []
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
}

//
//  AppState+Practice.swift
//  Kotek
//
//  Practice session flow, kotekan selection, and scoring/records lifecycle.
//

import Foundation
import OSLog

extension AppState {
    // MARK: - Kotekan Catalogue

    /// The figures the picker shows on the gangsa in play: the built-ins and
    /// the player's own filed on it. They used to be the account's, every
    /// figure on every gangsa — one made for a seven-bilah gangsa turned up on
    /// the ten-bilah one too. A figure is moved across by copying it
    /// (`copyKotekan`).
    var kotekansOnGangsa: [Kotekan] {
        kotekans.filter { $0.isFiled(on: profile) }
    }

    /// Swap in the database's catalogue, if it has one.
    func refreshCatalogue() async {
        do {
            let fetched = try await Kotekan.catalogue(from: kotekanRepo.catalogue())
            guard !fetched.isEmpty else { return }
            kotekans = fetched
            KotekanStore.save(fetched)
            if let id = selectedKotekan?.id {
                selectedKotekan = fetched.first { $0.id == id } ?? selectedKotekan
            }
        } catch {
            log.error("catalogue fetch failed, keeping the last one: \(error.localizedDescription)")
        }
    }

    /// File a figure from Create Kotek and land on it in the picker.
    ///
    /// Waits for the database rather than adding it locally and syncing behind:
    /// the catalogue is REPLACED by whatever Supabase holds on the next launch,
    /// so a figure that never reached it would vanish without a word. Throwing
    /// lets the review screen keep the work and say so.
    ///
    /// An edit has the same id as the figure it came from, so it replaces that
    /// figure — on the server (`saveKotekan` upserts) and in the rail.
    func saveKotekan(_ k: Kotekan) async throws {
        var k = k
        let instrument = profile
        let instrumentID = UUID(uuidString: instrument.id) == nil ? nil : instrument.id
        k.instrumentID = instrumentID
        // R The instrument goes up first, as it does before a practice
        // R session: `kotekan.instrument_id` points at `instruments`, and a
        // R player who writes a figure before ever finishing a session has
        // R never uploaded this gangsa — the save failed on the foreign key.
        if instrumentID != nil { try await instrumentRemote.saveInstrument(instrument) }
        try await kotekanRepo.saveKotekan(RemoteKotekan(k, source: k.source, instrumentID: instrumentID))
        if let i = kotekans.firstIndex(where: { $0.id == k.id }) {
            kotekans[i] = k
        } else {
            kotekans.append(k)
        }
        KotekanStore.save(kotekans)
        editingKotekan = nil
        selectedKotekan = k
        screen = .chooseKotekan
    }

    /// A copy of one of the player's own figures on another of their gangsa:
    /// a new id, so the two go their own ways after — editing one leaves the
    /// other. Stays on the gangsa in play; Kipli says where it went.
    func copyKotekan(_ k: Kotekan, to instrument: InstrumentProfile) async throws {
        guard k.source != .builtin else { return }
        var copy = k
        copy.id = UUID().uuidString.lowercased()
        copy.instrumentID = UUID(uuidString: instrument.id) == nil ? nil : instrument.id
        // Up first, as in `saveKotekan`: `kotekan.instrument_id` points at
        // `instruments`, and that gangsa may never have been uploaded.
        if copy.instrumentID != nil { try await instrumentRemote.saveInstrument(instrument) }
        try await kotekanRepo.saveKotekan(RemoteKotekan(copy, source: copy.source, instrumentID: copy.instrumentID))
        kotekans.append(copy)
        KotekanStore.save(kotekans)
        copyingKotekan = nil
        copiedNotice = "Copied \(k.name) to \(instrument.name). It's on that gangsa's rail now."
    }

    /// One of the player's own figures, from the server and the rail. Its
    /// records stay on the gangsa: harmless, and a figure re-made under a new
    /// id starts its own.
    func deleteKotekan(_ k: Kotekan) async throws {
        guard k.source != .builtin else { return }
        try await kotekanRepo.deleteKotekan(id: k.id)
        kotekans.removeAll { $0.id == k.id }
        KotekanStore.save(kotekans)
        if selectedKotekan?.id == k.id { selectedKotekan = nil }
    }

    // MARK: - Session Selection & Flow

    /// Take this figure into play on the waterfall. A pattern not yet
    /// learned opens into Learn; one that has been, into free play.
    func playKotekan(_ k: Kotekan) {
        if LearnProgress.isDone(k.id) {
            chooseKotekanWaterfall(k)
        } else {
            startLearn(k)
        }
    }

    /// Take this figure into the waterfall — the drawn gangsa, played from
    /// the sensors, no camera. No countdown route: the screen counts itself in.
    func chooseKotekanWaterfall(_ k: Kotekan) {
        selectedKotekan = k
        renderHalves()
        screen = .waterfall
    }

    /// Change sides without leaving the session.
    func setHalf(_ half: KotekanHalf) {
        guard half != chosenHalf else { return }
        chosenHalf = half
        renderHalves()
    }

    /// ONE cycle of each half. The engine repeats it for as long as the player wants.
    func renderHalves() {
        guard let k = selectedKotekan else { return }
        selectedSong = k.makeSong(half: chosenHalf, cycles: 1)
        partnerSong = k.makeSong(half: chosenHalf.other, cycles: 1)
    }

    func finish(result: SongResult) {
        fileRecord(result)
        recordSession(landed: result.landedNotes)
        lastResult = result
        screen = .results
        offerSaveIfDue()

        let session = PracticeSession(
            result: result,
            kotekan: selectedKotekan,
            half: chosenHalf,
            tempoScale: tempoScale,
            leniency: PlayEngine.standardLeniency
        )
        let instrument = profile
        Task { [sessionRepo, log] in
            do {
                try await sessionRepo.recordSession(session, on: instrument)
            } catch {
                log.error("session sync failed: \(error.localizedDescription)")
            }
        }
    }

    /// The results of a session played with no sensor: passes, time and
    /// tempo. Nothing is filed — there is no record or score to keep — so no
    /// save prompt either.
    func showUnscored(_ result: SongResult) {
        lastResult = result
        screen = .results
    }

    /// This figure and half's sessions on this gangsa from before `start`,
    /// newest first, with an accuracy — what Kipli compares the one just
    /// played with. Empty offline, signed out, or the first time.
    ///
    /// `start` because `finish` uploads the session just played at the same
    /// moment this reads, and it must not be compared with itself.
    func pastSessions(before start: Date) async -> [PracticeHistoryRow] {
        guard let k = selectedKotekan else { return [] }
        let half = chosenHalf.rawValue
        let rows = await (try? sessionRepo.history(instrumentID: profile.id)) ?? []
        return rows.filter {
            $0.kotekanID == k.id && $0.half == half && $0.accuracy != nil
                && (InstrumentProfile.date(from: $0.createdAt) ?? .distantFuture) < start
        }
    }

    /// File the session's best window as this figure's record, if it is one.
    func fileRecord(_ result: SongResult) {
        previousRecord = nil
        lastSetRecord = false
        guard let k = selectedKotekan,
              result.cycles.count >= SongResult.scoringWindow,
              let best = result.best
        else { return }

        let half = chosenHalf.rawValue
        previousRecord =
            profile.record(kotekanId: k.id, half: half, tempo: tempoScale)?
                .accuracy
        var updated = profile
        lastSetRecord = updated.noteRecord(
            kotekanId: k.id,
            half: half,
            tempo: tempoScale,
            accuracy: best.accuracy
        )
        guard lastSetRecord else { return }
        profile = updated
    }

    /// Fold a finished session into the active instrument.
    func recordSession(landed: Int) {
        var updated = profile
        updated.lastUsedAt = InstrumentProfile.nowISO()
        updated.sessionCount = updated.sessionsPlayed + 1
        updated.accurateNotes = updated.notesLanded + landed
        profile = updated
        saveProfile()
    }
}

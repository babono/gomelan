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

    /// Swap in the database's catalogue, if it has one.
    func refreshCatalogue() async {
        do {
            let fetched = try await Kotekan.catalogue(from: kotekanRepo.catalogue())
            guard !fetched.isEmpty else { return }
            kotekans = fetched
            if let id = selectedKotekan?.id {
                selectedKotekan = fetched.first { $0.id == id } ?? selectedKotekan
            }
        } catch {
            log.error("catalogue fetch failed, keeping bundled: \(error.localizedDescription)")
        }
    }

    /// File a figure from Create Kotek and land on it in the picker.
    ///
    /// Waits for the database rather than adding it locally and syncing behind:
    /// the catalogue is REPLACED by whatever Supabase holds on the next launch,
    /// so a figure that never reached it would vanish without a word. Throwing
    /// lets the review screen keep the work and say so.
    func saveKotekan(_ k: Kotekan) async throws {
        let instrumentID = UUID(uuidString: profile.id) == nil ? nil : profile.id
        try await kotekanRepo.saveKotekan(RemoteKotekan(k, source: k.source, instrumentID: instrumentID))
        kotekans.append(k)
        selectedKotekan = k
        screen = .chooseKotekan
    }

    // MARK: - Session Selection & Flow

    /// Take this figure into whichever play screen is current: the waterfall
    /// by default, the camera top view when `topView` is on.
    func playKotekan(_ k: Kotekan) {
        if topView { chooseKotekan(k) } else { chooseKotekanWaterfall(k) }
    }

    /// Take this figure and advance to countdown (the camera top view).
    func chooseKotekan(_ k: Kotekan) {
        selectedKotekan = k
        renderHalves()
        screen = .countdown
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

    func countdownFinished() {
        screen = .playing
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
            leniency: judgementLeniency
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

//
//  AppState+Share.swift
//  Kotek
//
//  A kotekan shared by link: opening it, and adding a copy to a gangsa. The
//  copy is the player's own from then on — not synced with the sender's — see
//  the kotekan share migration.
//

import Foundation

extension AppState {
    /// From `onOpenURL`. Any other link is ignored. Held until an account is
    /// chosen, so a link that opens a fresh install waits for the welcome screen.
    func openSharedKotekan(_ url: URL) {
        #if DEBUG
            KotekanLink.selfCheck()
        #endif
        guard let id = KotekanLink.id(from: url) else { return }
        pendingShare = id
    }

    /// Copy the shared figure onto `instrument`, switch to that gangsa and land
    /// on the copy in the picker. Throws so the dialog can stay up and say so.
    func addSharedKotekan(id: String, to instrument: InstrumentProfile) async throws {
        let instrumentID = UUID(uuidString: instrument.id) == nil ? nil : instrument.id
        // Up first, as in `saveKotekan`: `kotekan.instrument_id` points at
        // `instruments`, and a gangsa may never have been uploaded.
        if instrumentID != nil { try await instrumentRemote.saveInstrument(instrument) }
        let newID = try await kotekanRepo.copyShared(id: id, instrumentID: instrumentID)
        await refreshCatalogue()
        pendingShare = nil
        activateInstrument(instrument)
        selectedKotekan = kotekans.first { $0.id == newID } ?? selectedKotekan
        screen = .chooseKotekan
    }
}

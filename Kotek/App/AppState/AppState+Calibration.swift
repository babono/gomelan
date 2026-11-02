//
//  AppState+Calibration.swift
//  Kotek
//
//  Adding a gangsa, step 1: the key count.
//

import Foundation

extension AppState {
    // MARK: - Setup Flow

    /// Step 1: how many keys does this gangsa have, and what is it called?
    ///
    /// Goes straight on to recording the keys. The keys sit on the default
    /// `layout(count:)` from `resize(to:)`: nothing reads their rects since
    /// the camera play mode went, so nothing needs them fitted.
    /// `photo` is already prepared (`InstrumentPhotoStore.prepare`); nil leaves
    /// whatever photo the gangsa had.
    func keyCountChosen(_ count: Int, name: String, photo: Data?) {
        var updated = profile
        updated.resize(to: count)
        if let photo {
            let version = UUID().uuidString.lowercased()
            if (try? InstrumentPhotoStore.save(photo, id: updated.id, version: version)) != nil {
                updated.photoVersion = version
            }
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { updated.name = trimmed }
        profile = updated
        guard isAddingNewInstrument else {
            // Editing an existing gangsa: its name, photo and count.
            saveProfile()
            screen = .chooseKotekan
            return
        }
        // Not saved here: the gangsa is added when the whole setup is done
        // (`closeControllerSetup`), so backing out of a later step adds
        // nothing. On to recording its keys, then the controller (Flow D).
        //
        // R Framing, aligning the camera mask and learning the gangsa's voice
        // R (the strike-sound baseline) sat between here and there, then
        // R behind Settings for realigning by hand; they went with the camera
        // R play mode.
        openNoteCapture(setup: true)
    }
}

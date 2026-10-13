//
//  AppState+Calibration.swift
//  Kotek
//
//  Setup steps: key counting, framing, alignment, and acoustic baseline learning.
//

import Foundation

extension AppState {
    // MARK: - Setup Flow

    /// Step 1/2: how many keys does this gangsa have, and what is it called?
    ///
    /// Goes straight on to the voice (step 2/2). Framing and aligning the
    /// camera mask were dropped from adding a gangsa: the keys start on the
    /// default `layout(count:)` from `resize(to:)`, and `realign()` /
    /// `realignInstrument(_:)` still reach `.aligning` for anyone who wants
    /// the camera fit. The framing/aligning screens are kept, just unrouted
    /// from here.
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
        if !isAddingNewInstrument {
            saveProfile()
        }
        // ponytail: was `screen = .framing`; the camera fit is skipped, so this
        // is now the same hand-off the aligning step makes when it is done.
        alignmentConfirmed()
    }

    /// Framing → aligning. No longer reached when adding a gangsa.
    func framingConfirmed() {
        seedMasksFromFraming = true
        screen = .aligning
    }

    /// Aligning done (or skipped by `keyCountChosen`) → the baseline.
    func alignmentConfirmed() {
        if isAddingNewInstrument {
            isAddingNewInstrument = false
            previousProfile = nil
            offerControllerAfterSetup = true
        }
        if baselineLearned { finishSetup() } else { screen = .calibrating }
    }

    /// Baseline captured: strikes will now be confirmed by sound.
    func baselineFinished() {
        baselineLearned = true
        requireStrikeSound = true
        saveProfile()
        finishSetup()
    }

    /// As above, but awaits the write so the caller can hold a "saving" state over it.
    func baselineFinishedAsync() async {
        baselineLearned = true
        requireStrikeSound = true
        await saveProfileAsync()
        finishSetup()
    }

    /// Left the baseline step without capturing — continue anyway (vision alone).
    func skipCalibration() {
        saveProfile()
        finishSetup()
    }

    /// The end of setup. A gangsa set up just now is offered a strike
    /// controller once, as an optional last step (Flow D); everything else
    /// lands on the kotekan picker as before.
    private func finishSetup() {
        guard offerControllerAfterSetup else {
            screen = .chooseKotekan
            return
        }
        offerControllerAfterSetup = false
        openControllerSetup(returnTo: .chooseKotekan, offer: true)
    }
}

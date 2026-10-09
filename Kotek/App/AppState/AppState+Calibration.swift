//
//  AppState+Calibration.swift
//  Kotek
//
//  Setup steps: key counting, framing, alignment, and acoustic baseline learning.
//

import Foundation

extension AppState {
    // MARK: - Setup Flow

    /// Step 1/4: how many keys does this gangsa have, and what is it called?
    func keyCountChosen(_ count: Int, name: String, type: GangsaType) {
        var updated = profile
        updated.resize(to: count)
        updated.gangsaType = type
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { updated.name = trimmed }
        profile = updated
        if !isAddingNewInstrument {
            saveProfile()
        }
        screen = .framing
    }

    /// Step 2/4 → 3/4.
    func framingConfirmed() {
        seedMasksFromFraming = true
        screen = .aligning
    }

    /// Step 3/4 leads into the baseline (4/4).
    func alignmentConfirmed() {
        if isAddingNewInstrument {
            isAddingNewInstrument = false
            previousProfile = nil
        }
        screen = baselineLearned ? .chooseKotekan : .calibrating
    }

    /// Baseline captured: strikes will now be confirmed by sound.
    func baselineFinished() {
        baselineLearned = true
        requireStrikeSound = true
        saveProfile()
        screen = .chooseKotekan
    }

    /// As above, but awaits the write so the caller can hold a "saving" state over it.
    func baselineFinishedAsync() async {
        baselineLearned = true
        requireStrikeSound = true
        await saveProfileAsync()
        screen = .chooseKotekan
    }

    /// Left the baseline step without capturing — continue anyway (vision alone).
    func skipCalibration() {
        saveProfile()
        screen = .chooseKotekan
    }
}

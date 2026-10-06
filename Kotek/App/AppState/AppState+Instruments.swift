//
//  AppState+Instruments.swift
//  Kotek
//
//  Instrument profile selection, CRUD, and remote database sync.
//

import Foundation
import OSLog

extension AppState {
    // MARK: - Instrument Selection & Management

    /// Make this the active instrument without leaving the picker.
    func activateInstrument(_ p: InstrumentProfile) {
        profile = p
        ProfileStore.setSelectedID(p.id)
        baselineLearned = p.hasLearnedBaseline
        if !p.hasLearnedBaseline { requireStrikeSound = false }
    }

    /// Pick this instrument and advance to kotekan selection.
    func selectInstrument(_ p: InstrumentProfile) {
        activateInstrument(p)
        screen = .chooseKotekan
    }

    func addNewInstrument() {
        let count = savedProfiles.count + 1
        let newID = UUID().uuidString
        let name = "Gangsa #\(count)"
        let newProfile = InstrumentProfile(
            id: newID,
            name: name,
            keyCount: 10,
            createdAt: InstrumentProfile.nowISO(),
            keys: InstrumentProfile.layout(count: 10)
        )

        isAddingNewInstrument = true
        previousProfile = profile
        profile = newProfile
        screen = .choosingKeyCount
    }

    func cancelInstrumentSetup() {
        savedProfiles = ProfileStore.loadAll()
        if isAddingNewInstrument {
            if let prev = previousProfile,
                savedProfiles.contains(where: { $0.id == prev.id })
            {
                profile = prev
                ProfileStore.setSelectedID(prev.id)
            }
            isAddingNewInstrument = false
            previousProfile = nil
        }
        screen = .chooseInstrument
    }

    func realignInstrument(_ p: InstrumentProfile) {
        profile = p
        ProfileStore.setSelectedID(p.id)
        screen = .aligning
    }

    /// Delete an instrument, including the last one.
    func deleteInstrument(_ profileID: String) {
        ProfileStore.delete(profileID)
        savedProfiles = ProfileStore.loadAll()
        Task { [instrumentRemote, log] in
            do { try await instrumentRemote.deleteInstrument(id: profileID) } catch {
                log.error("instrument delete failed: \(error.localizedDescription)")
            }
        }

        if previousProfile?.id == profileID { previousProfile = nil }
        guard profile.id == profileID else { return }

        if let next = savedProfiles.first {
            profile = next
            ProfileStore.setSelectedID(next.id)
            baselineLearned = next.hasLearnedBaseline
            if !next.hasLearnedBaseline { requireStrikeSound = false }
        } else {
            profile = ResourceLoader.defaultProfile()
            ProfileStore.setSelectedID("")
            baselineLearned = false
            requireStrikeSound = false
        }
    }

    func openChooseInstrument() {
        savedProfiles = ProfileStore.loadAll()
        screen = .chooseInstrument
    }

    // MARK: - Profile Persistence & Remote Sync

    // ponytail: a failed write is logged and dropped, not queued. The launch
    // push re-sends every instrument, so only practice sessions played offline
    // are actually lost.
    func push(_ p: InstrumentProfile) async {
        do { try await instrumentRemote.saveInstrument(p) } catch {
            log.error("instrument sync failed: \(error.localizedDescription)")
        }
    }

    func pushInBackground(_ p: InstrumentProfile) {
        Task { await push(p) }
    }

    func saveProfile() {
        ProfileStore.save(profile)
        savedProfiles = ProfileStore.loadAll()
        pushInBackground(profile)
    }

    /// Save a specific instrument, which may not be the active one.
    func saveInstrument(_ p: InstrumentProfile) {
        ProfileStore.save(p)
        ProfileStore.setSelectedID(profile.id)
        savedProfiles = ProfileStore.loadAll()
        pushInBackground(p)
    }

    /// Fold the audio dictionary a session learned back into the instrument.
    func storeLinearTemplates(_ atoms: [Int: LearnedAtom]) {
        guard !atoms.isEmpty else { return }
        var changed = false
        for (index, atom) in atoms {
            guard
                let position = profile.keys.firstIndex(where: {
                    $0.index == index
                })
            else { continue }
            if profile.keys[position].linearTemplate != atom.bands
                || profile.keys[position].linearTemplateCount != atom.examples
            {
                profile.keys[position].linearTemplate = atom.bands
                profile.keys[position].linearTemplateCount = atom.examples
                changed = true
            }
        }
        guard changed else { return }
        saveProfile()
    }

    /// The same save, off the main actor for loading spinners.
    func saveProfileAsync() async {
        let snapshot = profile
        savedProfiles = await Task.detached {
            ProfileStore.save(snapshot)
            return ProfileStore.loadAll()
        }.value
        pushInBackground(snapshot)
    }

    /// Kotekan this instrument has enough keys for.
    func kotekan(_ k: Kotekan, playableOn profile: InstrumentProfile) -> Bool {
        k.requiredKeys <= profile.keyCount
    }
}

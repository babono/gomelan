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
        let photo = savedProfiles.first { $0.id == profileID }?.photoVersion
        ProfileStore.delete(profileID)
        InstrumentPhotoStore.delete(id: profileID)
        NoteClipCapture.deleteInstrument(instrumentID: profileID)
        savedProfiles = ProfileStore.loadAll()
        Task { [instrumentRemote, log] in
            do {
                try await instrumentRemote.deleteInstrument(id: profileID)
                if let photo { try await instrumentRemote.deletePhoto(id: profileID, version: photo) }
            } catch {
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
    // sync re-sends every instrument the server is behind on, so only practice
    // sessions played offline are actually lost.
    @discardableResult
    func push(_ p: InstrumentProfile) async -> Bool {
        do {
            try await instrumentRemote.saveInstrument(p)
            await uploadPhotoIfNeeded(p)
            await uploadSoundsIfNeeded(p)
            return true
        } catch {
            log.error("instrument sync failed: \(error.localizedDescription)")
            return false
        }
    }

    func pushInBackground(_ p: InstrumentProfile) {
        Task { await push(p) }
    }

    func saveProfile() {
        profile = ProfileStore.save(profile)
        savedProfiles = ProfileStore.loadAll()
        pushInBackground(profile)
    }

    /// Save a specific instrument, which may not be the active one.
    func saveInstrument(_ p: InstrumentProfile) {
        let saved = ProfileStore.save(p)
        ProfileStore.setSelectedID(profile.id)
        savedProfiles = ProfileStore.loadAll()
        pushInBackground(saved)
    }

    /// IDs of the instruments the server has confirmed holding. The only way
    /// to tell "deleted on my other phone" from "made here and not uploaded
    /// yet" — both are simply missing from the download — without keeping
    /// deletion records on the server.
    static var syncedInstrumentIDs: Set<String> {
        get { Set(Defaults.strings("syncedInstrumentIDs")) }
        set { Defaults.set("syncedInstrumentIDs", Array(newValue)) }
    }

    /// Bring this phone and the server into agreement.
    ///
    /// Apple accounts only: they are the ones that can be on two phones. For
    /// each instrument the copy changed most recently wins, whichever side it
    /// is on — so an iPad realigned this morning is not undone by a phone that
    /// has not been opened since last week. A guest only pushes, as before.
    func syncInstruments() async {
        let local = ProfileStore.loadAll()
        guard account == .apple else {
            for p in local {
                await push(p)
            }
            return
        }
        let remote: [(id: String, profile: InstrumentProfile?)]
        do {
            remote = try await instrumentRemote.fetchInstruments()
        } catch {
            // Offline, most likely. Do what a guest does; the next launch
            // will reconcile.
            log.error("instrument download failed: \(error.localizedDescription)")
            for p in local {
                await push(p)
            }
            return
        }

        let localByID = Dictionary(local.map { ($0.id.uppercased(), $0) }) { a, _ in a }
        let remoteIDs = Set(remote.map { $0.id.uppercased() })
        let synced = Set(Self.syncedInstrumentIDs.map { $0.uppercased() })
        var merged: [InstrumentProfile] = []
        var toPush: [InstrumentProfile] = []

        for (id, theirs) in remote {
            guard let mine = localByID[id.uppercased()] else {
                // Nil `theirs` is a row from before the full profile went up:
                // nothing to restore from.
                if let theirs { merged.append(theirs) }
                continue
            }
            if let theirs, theirs.modifiedAt > mine.modifiedAt {
                merged.append(theirs)
            } else {
                merged.append(mine)
                // A tie is already in step; anything else, the server is behind.
                if theirs.map({ mine.modifiedAt > $0.modifiedAt }) ?? true { toPush.append(mine) }
            }
        }
        for mine in local where !remoteIDs.contains(mine.id.uppercased()) {
            // Gone from the server after it once held it: deleted elsewhere.
            if synced.contains(mine.id.uppercased()) { continue }
            merged.append(mine)
            toPush.append(mine)
        }

        ProfileStore.saveAll(merged)
        // Deleted on another device: its note clips go with it.
        let keptIDs = Set(merged.map(\.id))
        for gone in local where !keptIDs.contains(gone.id) {
            NoteClipCapture.deleteInstrument(instrumentID: gone.id)
        }
        savedProfiles = ProfileStore.loadAll()
        adoptSyncedActiveProfile()
        await downloadMissingPhotos(merged)
        await downloadMissingSounds(merged)

        var confirmed = remoteIDs
        for p in toPush {
            // Instruments without a UUID are never uploaded (see
            // `saveInstrument`), so a "successful" push is not a confirmation.
            if await push(p), UUID(uuidString: p.id) != nil {
                confirmed.insert(p.id.uppercased())
            }
        }
        Self.syncedInstrumentIDs = confirmed
    }

    /// The active instrument may have been replaced by a newer copy, or
    /// deleted elsewhere. Left alone mid-setup: that profile is not saved yet,
    /// and swapping it out would lose the step the player is on.
    private func adoptSyncedActiveProfile() {
        guard !isAddingNewInstrument else { return }
        if let current = savedProfiles.first(where: { $0.id == profile.id }) {
            if current != profile { activateInstrument(current) }
        } else if let next = ProfileStore.loadSelected() {
            activateInstrument(next)
        }
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
        let (saved, all) = await Task.detached {
            (ProfileStore.save(snapshot), ProfileStore.loadAll())
        }.value
        savedProfiles = all
        profile = saved
        pushInBackground(saved)
    }

    // MARK: - Photos

    /// A new photo for a gangsa: on this phone at once, up to the server with
    /// the profile it belongs to.
    func setPhoto(_ jpeg: Data, for id: String) {
        let version = UUID().uuidString.lowercased()
        do {
            try InstrumentPhotoStore.save(jpeg, id: id, version: version)
        } catch {
            log.error("photo save failed: \(error.localizedDescription)")
            return
        }
        if profile.id == id {
            profile.photoVersion = version
            saveProfile()
        } else if var other = savedProfiles.first(where: { $0.id == id }) {
            other.photoVersion = version
            saveInstrument(other)
        }
    }

    /// The version last uploaded for each gangsa, so a push re-sends the photo
    /// only when it has changed — and a failed upload is tried again on the
    /// next push, because nothing was recorded for it.
    private static func uploadedPhoto(_ id: String) -> String? {
        Defaults.string("uploadedPhoto.\(id.lowercased())")
    }

    private func uploadPhotoIfNeeded(_ p: InstrumentProfile) async {
        guard let version = p.photoVersion, UUID(uuidString: p.id) != nil,
              Self.uploadedPhoto(p.id) != version,
              let jpeg = InstrumentPhotoStore.data(id: p.id, version: version)
        else { return }
        let previous = Self.uploadedPhoto(p.id)
        do {
            try await instrumentRemote.uploadPhoto(jpeg, id: p.id, version: version)
            Defaults.set("uploadedPhoto.\(p.id.lowercased())", version)
            // The old one is unreachable now — no profile names it.
            if let previous { try? await instrumentRemote.deletePhoto(id: p.id, version: previous) }
        } catch {
            log.error("photo upload failed: \(error.localizedDescription)")
        }
    }

    /// Photos another phone added or changed. A miss — offline, or the other
    /// phone has not finished uploading — is simply tried on the next sync.
    private func downloadMissingPhotos(_ profiles: [InstrumentProfile]) async {
        for p in profiles {
            guard let version = p.photoVersion, !InstrumentPhotoStore.has(id: p.id, version: version) else { continue }
            do {
                let jpeg = try await instrumentRemote.downloadPhoto(id: p.id, version: version)
                try InstrumentPhotoStore.save(jpeg, id: p.id, version: version)
                Defaults.set("uploadedPhoto.\(p.id.lowercased())", version)
            } catch {
                log.error("photo download failed: \(error.localizedDescription)")
            }
        }
        // Redraw the cards with what arrived.
        savedProfiles = ProfileStore.loadAll()
    }

    // MARK: - Recorded key sounds

    /// This key now plays the recording `file`, or the bundled sample for nil.
    /// Saving the profile pushes it, and the push uploads the clip.
    func setSound(_ file: String?, forKey index: Int) {
        guard let at = profile.keys.firstIndex(where: { $0.index == index }) else { return }
        let previous = profile.keys[at].soundFile
        profile.keys[at].soundFile = file
        saveProfile()
        // A replaced take is cleaned up by the upload; only a removal needs it here.
        guard file == nil, let previous, UUID(uuidString: profile.id) != nil else { return }
        let id = profile.id
        Task { [instrumentRemote, log] in
            do {
                try await instrumentRemote.deleteSound(instrumentID: id, file: previous)
            } catch {
                log.error("sound delete failed: \(error.localizedDescription)")
            }
        }
    }

    /// The take last uploaded for each key, so a push sends a clip once and a
    /// failed upload is tried again on the next push.
    private static func uploadedSound(_ id: String, key: Int) -> String? {
        Defaults.string("uploadedSound.\(id.lowercased()).\(key)")
    }

    private func uploadSoundsIfNeeded(_ p: InstrumentProfile) async {
        guard UUID(uuidString: p.id) != nil else { return }
        // One key at a time: at most ten ~265 kB clips, and a failure on one
        // should not stop the rest.
        for key in p.keys {
            guard let file = key.soundFile, Self.uploadedSound(p.id, key: key.index) != file,
                  let wav = await NoteClipCapture.data(instrumentID: p.id, keyIndex: key.index, file: file)
            else { continue }
            let previous = Self.uploadedSound(p.id, key: key.index)
            do {
                try await instrumentRemote.uploadSound(wav, instrumentID: p.id, file: file)
                Defaults.set("uploadedSound.\(p.id.lowercased()).\(key.index)", file)
                // The old take is unreachable now — no profile names it.
                if let previous { try? await instrumentRemote.deleteSound(instrumentID: p.id, file: previous) }
            } catch {
                log.error("sound upload failed: \(error.localizedDescription)")
            }
        }
    }

    /// Recordings another phone made. A miss is simply tried on the next sync.
    private func downloadMissingSounds(_ profiles: [InstrumentProfile]) async {
        for p in profiles {
            for key in p.keys {
                guard let file = key.soundFile,
                      !NoteClipCapture.hasClip(instrumentID: p.id, keyIndex: key.index, file: file)
                else { continue }
                do {
                    let wav = try await instrumentRemote.downloadSound(instrumentID: p.id, file: file)
                    try await NoteClipCapture.install(wav, instrumentID: p.id, keyIndex: key.index, file: file)
                    Defaults.set("uploadedSound.\(p.id.lowercased()).\(key.index)", file)
                } catch {
                    log.error("sound download failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Kotekan this instrument has enough keys for.
    func kotekan(_ k: Kotekan, playableOn profile: InstrumentProfile) -> Bool {
        k.requiredKeys <= profile.keyCount
    }
}

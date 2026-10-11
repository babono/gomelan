//
//  AppState+Account.swift
//  Kotek
//
//  Guest or Apple ID: the choice on the welcome screen, linking a guest up from
//  Settings, signing out, and the one-time v2 reset. Nothing talks to Supabase
//  until the choice is made — see `startSync`.
//

import FactoryKit
import Foundation
import OSLog

extension AppState {
    enum Account: String {
        case guest
        case apple
    }

    /// Bumped when local data from an older release must not survive the
    /// update. 2: v1 progress was dropped wholesale rather than migrated into
    /// the accounts v2 introduced.
    private static let dataEpoch = 2

    // MARK: - Launch

    /// Run from `init`, BEFORE the profiles are loaded, so a reset launch reads
    /// an empty store instead of loading the old one and then clearing it.
    /// Static for the same reason: `self` is not initialised yet.
    ///
    /// Also fires on a fresh install, where it is what stops a session left in
    /// the keychain — which outlives deleting the app — from quietly signing a
    /// new "guest" back in as whoever used the phone before.
    static func resetLocalDataIfStale() {
        guard Defaults.int("dataEpoch", 1) < Self.dataEpoch else { return }
        ProfileStore.reset()
        Defaults.set("dataEpoch", Self.dataEpoch)
        Defaults.set("account", "")
        // ponytail: not awaited. The SDK drops the stored session before its
        // first suspension, long before anyone can get past the splash and
        // pick guest — and awaiting it would hold the launch on a network call.
        Task { await Container.shared.authRepository().signOut() }
    }

    /// The network half of launch, deferred until there is someone to sync as.
    /// Before the choice, fetching the catalogue would sign in anonymously and
    /// leave an orphaned guest behind every player who goes on to pick Apple.
    func startSync() {
        let pending = savedProfiles
        Task {
            await refreshCatalogue()
            for p in pending {
                await push(p)
            }
        }
    }

    // MARK: - The Choice

    func continueAsGuest() {
        setAccount(.guest)
        startSync()
        begin()
    }

    /// From the welcome screen. Nothing is on the phone yet, so there is no
    /// guest to link and nothing to warn about.
    func signInWithApple(idToken: String, nonce: String) async {
        accountError = nil
        accountBusy = "Signing in…"
        defer { accountBusy = nil }
        do {
            try await auth.signInWithApple(idToken: idToken, nonce: nonce, linkingGuest: false)
            setAccount(.apple)
            startSync()
            begin()
        } catch {
            accountError = "Couldn't sign in with Apple. Check your connection and try again."
            log.error("apple sign-in failed: \(error.localizedDescription)")
        }
    }

    /// From Settings: attach the Apple ID to this guest, keeping everything.
    func linkApple(idToken: String, nonce: String) async {
        accountError = nil
        accountBusy = "Linking…"
        defer { accountBusy = nil }
        do {
            try await auth.signInWithApple(idToken: idToken, nonce: nonce, linkingGuest: true)
            setAccount(.apple)
        } catch let existing as AuthRepository.AccountExists {
            pendingSwitch = existing
        } catch {
            accountError = "Couldn't link your Apple ID. Check your connection and try again."
            log.error("apple link failed: \(error.localizedDescription)")
        }
    }

    /// The Apple ID already had an account, and the player chose it over the
    /// guest. No merge: two progress histories for one gangsa cannot be
    /// reconciled sensibly, so this phone's is dropped (it was warned).
    func confirmSwitch(_ existing: AuthRepository.AccountExists) async {
        pendingSwitch = nil
        accountError = nil
        accountBusy = "Switching…"
        defer { accountBusy = nil }
        do {
            try await auth.switchToApple(existing)
            wipeLocalData()
            setAccount(.apple)
            startSync()
        } catch {
            // The guest was signed out first, so a failure here leaves no one
            // signed in. The local data is still here and syncs as a fresh
            // guest the next time anything is saved.
            accountError = "Couldn't switch accounts. Check your connection and try again."
            log.error("account switch failed: \(error.localizedDescription)")
        }
    }

    /// Back to the welcome screen with nothing on the phone.
    func signOut() {
        accountError = nil
        wipeLocalData()
        setAccount(nil)
        Task { [auth] in await auth.signOut() }
        screen = .welcome
    }

    // MARK: - Helpers

    private func setAccount(_ value: Account?) {
        account = value
        Defaults.set("account", value?.rawValue ?? "")
    }

    /// Everything that is the player's progress. Onboarding and detection
    /// tuning are left alone: they belong to the phone, not the account.
    private func wipeLocalData() {
        ProfileStore.reset()
        savedProfiles = []
        profile = ResourceLoader.defaultProfile()
        previousProfile = nil
        baselineLearned = false
        requireStrikeSound = false
        kotekans = Kotekan.bundled
        selectedKotekan = nil
        lastResult = nil
    }
}

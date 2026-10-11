//
//  AuthRepository.swift
//  Kotek
//
//  Who the player is to Supabase: a guest (an anonymous user, created lazily by
//  `SupabaseRepository.userID()` the first time something syncs) or an Apple
//  ID. Shared by the welcome screen, where the choice is first made, and
//  Settings, where a guest links up later.
//

import Foundation
import Supabase

nonisolated struct AuthRepository {
    private let remote: SupabaseRepository

    init(remote: SupabaseRepository = SupabaseRepository()) {
        self.remote = remote
    }

    /// The Apple ID is already someone's account, so it cannot be linked to
    /// this guest. Carries the token so the switch does not need a second
    /// trip through the Apple sheet.
    struct AccountExists: Error {
        let idToken: String
        let nonce: String
    }

    /// Whether the stored session is an Apple one. Read from the keychain
    /// without a network call.
    var isSignedInWithApple: Bool {
        remote.client.auth.currentUser.map { !$0.isAnonymous } ?? false
    }

    /// What the player chose on the profile step.
    struct Player {
        var name: String?
        var avatar: String?
    }

    /// Kept in the account's user metadata rather than a table of its own: it
    /// rides along with the session, so a second phone has it the moment it
    /// signs in, and it reads from the keychain offline.
    ///
    /// ponytail: user metadata is private to its owner. A leaderboard will need
    /// a public `profiles` table; copy these two fields into it then.
    var player: Player {
        let metadata = remote.client.auth.currentUser?.userMetadata ?? [:]
        return Player(
            name: metadata["display_name"]?.stringValue,
            avatar: metadata["avatar"]?.stringValue
        )
    }

    /// Merged into the metadata server-side, so nil leaves a field alone.
    /// `display_name` is also what the dashboard's Users list shows.
    func savePlayer(name: String?, avatar: String?) async throws {
        var data: [String: AnyJSON] = [:]
        if let name { data["display_name"] = .string(name) }
        if let avatar { data["avatar"] = .string(avatar) }
        guard !data.isEmpty else { return }
        try await remote.client.auth.update(user: UserAttributes(data: data))
    }

    /// Sign in with an Apple ID token.
    ///
    /// `linkingGuest` is the Settings path: the token is attached to the guest
    /// so the user id — and every row already uploaded under it — stays the
    /// same. The guest is made first if it never got as far as the network,
    /// because signing straight in would fold this phone's guest progress into
    /// an existing account instead of asking. From the welcome screen there is
    /// nothing local to keep, so it signs in directly rather than minting an
    /// anonymous user only to throw it away.
    func signInWithApple(idToken: String, nonce: String, linkingGuest: Bool) async throws {
        let credentials = OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        guard linkingGuest else {
            try await remote.client.auth.signInWithIdToken(credentials: credentials)
            return
        }
        _ = try await remote.userID()
        do {
            try await remote.client.auth.linkIdentityWithIdToken(credentials: credentials)
        } catch let error as AuthError where error.errorCode == .identityAlreadyExists {
            throw AccountExists(idToken: idToken, nonce: nonce)
        }
    }

    /// Leave the guest behind and become the account the Apple ID already has.
    /// The guest's rows stay on the server under a user nobody can sign in as.
    func switchToApple(_ existing: AccountExists) async throws {
        await signOut()
        try await remote.client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: existing.idToken,
                nonce: existing.nonce
            )
        )
    }

    /// Forget the session on this phone.
    ///
    /// Local scope: other devices signed in to the same account stay signed in.
    /// Errors are dropped because the SDK removes the stored session BEFORE it
    /// tells the server, so offline the sign-out has still happened here — the
    /// server's copy simply expires.
    func signOut() async {
        try? await remote.client.auth.signOut(scope: .local)
    }
}

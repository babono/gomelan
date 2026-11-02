//
//  AccountSectionView.swift
//  Kotek
//
//  Settings card for the account: a guest links an Apple ID here, an Apple
//  account signs out here.
//

import SwiftUI

struct AccountSectionView: View {
    @Bindable var viewModel: SettingsViewModel

    private var app: AppState {
        viewModel.app
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if app.account == .apple {
                HStack(spacing: 14) {
                    AvatarView(avatar: app.playerAvatar, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.playerName ?? String(localized: "No name yet"))
                            .font(.serif(22))
                            .foregroundStyle(Theme.heading)
                        Label("Signed in with Apple", systemImage: "apple.logo")
                            .font(.sans(13))
                            .foregroundStyle(Theme.cream.opacity(0.62))
                    }
                }

                FlowLayout(spacing: 10) {
                    AppButton(title: "Edit profile", systemImage: "person.crop.circle", size: .compact) {
                        app.openProfileSetup(returnTo: .settings)
                    }
                    AppButton(title: "Sign out", systemImage: "rectangle.portrait.and.arrow.right", size: .compact) {
                        viewModel.showSignOutConfirm = true
                    }
                }

                // Same treatment as deleting a gangsa: red, apart, and behind
                // a confirmation.
                AppButton(
                    title: "Delete account",
                    systemImage: "trash",
                    size: .compact,
                    tint: Theme.miss,
                    role: .destructive
                ) {
                    viewModel.showDeleteAccountConfirm = true
                }
                .padding(.top, 4)
            } else {
                // Said plainly, because nothing else will say it: a guest
                // finds out their progress was only on this phone the day
                // they delete the app.
                Label("Guest · not backed up", systemImage: "exclamationmark.icloud")
                    .font(.sans(16, weight: .medium))
                    .foregroundStyle(Theme.destructive)

                Text(
                    "Only saved on this iPhone. Sign in with Apple to keep your data safe."
                )
                .font(.sans(13))
                .foregroundStyle(Theme.cream.opacity(0.75))
                .frame(maxWidth: 360, alignment: .leading)

                AppleSignInButton { token, nonce, name in
                    Task { await app.linkApple(idToken: token, nonce: nonce, fullName: name, from: .settings) }
                } onError: { _ in
                    app.accountError = String(localized: "Couldn't link your Apple ID. Try again.")
                }
            }

            if let error = app.accountError {
                Text(error)
                    .font(.sans(13))
                    .foregroundStyle(Theme.miss)
            }
        }
    }
}

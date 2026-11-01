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
                            .foregroundStyle(Theme.cream)
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
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkle")
                        .font(.symbol(16, weight: .medium))
                        .foregroundStyle(Theme.gold)
                        .frame(width: 38, height: 38)
                        .overlay(Circle().strokeBorder(
                            Theme.cream.opacity(0.4),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        ))
                    Text(
                        "You're playing as a guest. Sign in and I'll keep your gangsa, kotek and progress on all your devices."
                    )
                    .font(.sans(14))
                    .foregroundStyle(Theme.cream.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                        Theme.cream.opacity(0.15),
                        lineWidth: 1
                    ))
                }

                // Under the bubble, at its right edge: beside the words it
                // squeezed them into a column, and inside the bubble it read
                // as part of the message rather than the thing to tap.
                AppleSignInButton(
                    onToken: { token, nonce, name in
                        Task { await app.linkApple(idToken: token, nonce: nonce, fullName: name, from: .settings) }
                    },
                    onError: { _ in
                        app.accountError = String(localized: "Couldn't link your Apple ID. Try again.")
                    },
                    size: .compact,
                    signIn: true
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if let error = app.accountError {
                Text(error)
                    .font(.sans(13))
                    .foregroundStyle(Theme.miss)
            }

            SettingsGroup(header: "General") {
                // Kotek's page in the Settings app, where iOS lists Language
                // for any app with more than one. That page is as deep as an
                // app may link: the language list itself is one tap further,
                // and only private URLs (rejected in review) reach it.
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    SettingsRow(title: "Language", divider: false) {
                        HStack(spacing: 6) {
                            Text(verbatim: Self.languageName)
                                .font(.sans(14))
                                .foregroundStyle(Theme.stone)
                            Image(systemName: "chevron.right")
                                .font(.symbol(12, weight: .semibold))
                                .foregroundStyle(Theme.stone)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.appPlain)
            }
            .padding(.top, 10)

            SettingsGroup(header: "About") {
                SettingsRow(title: "Version", subtitle: "Kotek \(Self.version)", divider: false) { EmptyView() }
            }
        }
    }

    /// The app's language, named in itself: "Bahasa Indonesia", "English".
    /// Indonesian by hand: Foundation names it "Indonesia", the country.
    private static var languageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        if code == "id" { return "Bahasa Indonesia" }
        let name = Locale(identifier: code).localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

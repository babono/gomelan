//
//  ShareSignInView.swift
//  Kotek
//
//  A guest opening a shared kotekan's link: sharing is between accounts, so
//  they link an Apple ID first. The add screen's own look — paper, the top
//  bar, a card where the figure will be, Kipli and Apple's button — rather
//  than `LinkApplePrompt`'s dialog, which it was: the same link opened two
//  screens that did not look related.
//
//  Once linked it stays up and becomes the add screen itself (`app.account`
//  changes under `AddSharedKotekanView`), so the player picks up where the
//  link left them.
//

import SwiftUI

struct ShareSignInView: View {
    /// Where the player lands again once linked; see `AppState.linkApple`.
    let origin: Route
    /// False hands Apple's token to no one: Settings › Debug's preview, on a
    /// phone whose account may be linked already. Then the button only closes.
    var linksAccount = true
    let onClose: () -> Void

    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                title: "Sign in to add it",
                subtitle: "Sharing is between accounts, so it can follow you to every device.",
                onBack: onClose
            )

            HStack(alignment: .center, spacing: 28) {
                waitingCard

                VStack(alignment: .leading, spacing: 14) {
                    KipliGuide(
                        message: "Someone shared a kotekan with you! Link your Apple ID and I'll put it on your gangsa."
                    )
                    AppleSignInButton(onToken: linked, onError: failed, size: .regular, signIn: true)
                }
                .frame(width: 320)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background { PatternBackground().ignoresSafeArea() }
    }

    /// Where the figure will be: its name and notes are behind the sign-in.
    private var waitingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Waiting for you", systemImage: "lock")
                .font(.sans(12, weight: .semibold))
                .foregroundStyle(Theme.cream)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.deep, in: Capsule())

            Text("A shared kotekan")
                .font(.serif(26))
                .foregroundStyle(Theme.description)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("Its name and notes open once you're signed in.")
                .font(.sans(13))
                .foregroundStyle(Theme.description)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: SharedKotekanCard.width, height: 190, alignment: .topLeading)
        .tactile(
            RoundedRectangle(cornerRadius: 20),
            fill: Theme.surface,
            outline: Theme.hairline,
            outlineWidth: 1.5,
            base: Theme.hairline,
            depth: 5
        )
        .accessibilityElement(children: .combine)
    }

    private func linked(token: String, nonce: String, name: String?) {
        guard linksAccount else { return onClose() }
        Task {
            await app.linkApple(idToken: token, nonce: nonce, fullName: name, from: origin)
        }
    }

    private func failed(_: Error) {
        app.accountError = String(localized: "Couldn't link your Apple ID. Try again from Settings.")
        onClose()
    }
}

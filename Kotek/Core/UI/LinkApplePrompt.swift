//
//  LinkApplePrompt.swift
//  Kotek
//
//  A guest asked to link an Apple ID, over whatever wanted one: keeping a
//  record on the results screen, sharing a kotekan, adding a shared one. Laid
//  out like `ConfirmDialog` so it reads as the same family, but the action is
//  Apple's own button — and declining is a plain "Not now", not a cancel: the
//  same offer stays in Settings.
//

import SwiftUI

struct LinkApplePrompt: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    /// Where the player lands again once linked; see `AppState.linkApple`.
    let origin: Route
    /// Instead of closing when Apple hands back a token. The add-shared
    /// dialog stays up through the link and turns into itself once signed in.
    var onLink: (() -> Void)?
    /// Either answer, and a failed link, close it.
    let onClose: () -> Void

    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture {
                    KajarTick.strike()
                    onClose()
                }

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.serif(24))
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(Theme.heading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(message)
                    .font(.sans(14))
                    .foregroundStyle(Theme.cream.opacity(0.75))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    AppButton(title: "Not now", size: .compact, action: onClose)
                    AppleSignInButton { token, nonce, name in
                        (onLink ?? onClose)()
                        Task {
                            await app.linkApple(idToken: token, nonce: nonce, fullName: name, from: origin)
                        }
                    } onError: { _ in
                        app.accountError = String(localized: "Couldn't link your Apple ID. Try again from Settings.")
                        onClose()
                    }
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Theme.cream.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
            .padding(.horizontal, 28)
        }
    }
}

//
//  SaveProgressPrompt.swift
//  Kotek
//
//  The one-time "keep this" ask for guests, over the results screen. Laid out
//  like `ConfirmDialog` so it reads as the same family, but the action is
//  Apple's own button — and declining is a plain "Not now", not a cancel: the
//  same offer stays in Settings.
//

import SwiftUI

struct SaveProgressPrompt: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture {
                    KajarTick.strike()
                    app.dismissSavePrompt()
                }

            VStack(alignment: .leading, spacing: 10) {
                Text(app.lastSetRecord ? "New record — keep it?" : "Keep your progress?")
                    .font(.serif(24))
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(
                    "As a guest, your gangsa and records are only on this iPhone. Link an Apple ID to keep them if you delete the app or change phones."
                )
                .font(.sans(14))
                .foregroundStyle(Theme.cream.opacity(0.75))
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    AppButton("Not now") {
                        app.dismissSavePrompt()
                    }
                    AppleSignInButton { token, nonce, name in
                        app.dismissSavePrompt()
                        Task {
                            await app.linkApple(idToken: token, nonce: nonce, fullName: name, from: .results)
                        }
                    } onError: { _ in
                        app.accountError = "Couldn't link your Apple ID. Try again from Settings."
                        app.dismissSavePrompt()
                    }
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .background(Theme.deep, in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Theme.cream.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
            .padding(.horizontal, 28)
        }
    }
}

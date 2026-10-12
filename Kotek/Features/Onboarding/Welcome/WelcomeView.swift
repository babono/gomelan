//
//  WelcomeView.swift
//  Kotek
//
//  Entry screen (PRD §8), built to the Kotek design: the wordmark over the
//  drifting pattern, one cream key to press, and a pelawah rising from the
//  bottom edge.
//

import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var app
    @State private var music = TitleMusic()
    /// Lives here rather than with the splash screen it belongs to, because
    /// this is the one place in launch where starting a sound is known to
    /// work — the music bed has always been audible from here. See SplashChime.
    @State private var chime = SplashChime()

    /// Where the gamelan bed sits while the opening kempur is ringing.
    private static let duckedMusicLevel: Float = 0.4
    private static let cornerHeight: CGFloat = 40

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height

            ZStack {
                // Ornaments() — held out, see OrnamentsView.swift

                VStack(spacing: 0) {
                    Spacer().frame(height: KotekWordmark.topInset(in: h))

                    KotekWordmark(
                        width: KotekWordmark.width(in: proxy.size.width)
                    )

                    // Half the gap while the choice is up: its hint line
                    // has to clear the pelawah, which rises to a fixed height
                    // whatever the screen.
                    Spacer().frame(height: h * (app.account == nil ? 0.03 : 0.07))

                    if app.account == nil {
                        accountChoice
                    } else {
                        PillButton(
                            title: "Get started",
                            trailingSystemImage: "arrow.right",
                            style: .filled
                        ) {
                            music.stop()
                            app.begin()
                        }
                        .fixedSize()
                    }

                    Spacer()
                }

                // Corner affordances: help and collaborator colophon
                VStack {
                    HStack(spacing: 2) {
                        Spacer()
                        howItWorks
                        collaborator
                    }
                    Spacer()
                }
                .padding(.top, 14)
                .padding(.trailing, 22)

                // Pelawah rising from bottom edge
                VStack {
                    Spacer()
                    Pelawah()
                        .frame(
                            width: min(470, proxy.size.width * 0.54),
                            height: 142
                        )
                        .offset(y: 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .task {
            await chime.strike()
        }
        .task {
            await music.start(volume: Self.duckedMusicLevel)
        }
        .task {
            try? await Task.sleep(for: .seconds(SplashChime.totalDuration))
            music.setLevel(1.0, fadeDuration: 1.8)
        }
        .onDisappear {
            music.stop()
            Task { @concurrent in
                await AudioSessionManager.configure()
            }
        }
    }

    // MARK: - Account Choice

    /// Shown in place of "Get started" until the player has picked one. Two
    /// equal doors rather than a sign-in wall with a small way round it: an
    /// account is encouraged, never required, and someone who has just set the
    /// phone up over a gangsa wants to play.
    private var accountChoice: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                AppleSignInButton { token, nonce, name in
                    music.stop()
                    Task { await app.signInWithApple(idToken: token, nonce: nonce, fullName: name) }
                } onError: { _ in
                    app.accountError = "Couldn't sign in with Apple. Try again."
                }

                PillButton(title: "Continue as guest", style: .outlined, uppercase: false) {
                    music.stop()
                    app.continueAsGuest()
                }
                .fixedSize()
            }

            Text(app.accountError ?? "As a guest, your progress stays on this iPhone only.")
                .font(.sans(12))
                .foregroundStyle(app.accountError == nil ? Theme.cream.opacity(0.62) : Theme.miss)
        }
    }

    // MARK: - Corner Affordances

    private func cornerButton(
        _ label: String,
        hint: String,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> some View
    ) -> some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 12)
                .frame(height: Self.cornerHeight)
                .background(
                    Theme.cream.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: Theme.radius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius)
                        .strokeBorder(Theme.cream.opacity(0.2), lineWidth: 1)
                )
                .frame(minHeight: 44)
                .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.kajar)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }

    private var collaborator: some View {
        cornerButton(
            "About Mekar Bhuana",
            hint: "Opens a short introduction",
            action: { app.openGuide(.mekarBhuana) }
        ) {
            Image("logo-mekarbhuana")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 22)
        }
    }

    private var howItWorks: some View {
        Button {
            app.openOnboarding()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.symbol(19, weight: .medium))
                .foregroundStyle(Theme.cream.opacity(0.72))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.kajar)
        .accessibilityLabel("How Kotek works")
        .accessibilityHint("Replays the introduction")
    }
}

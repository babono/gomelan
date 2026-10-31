//
//  WelcomeView.swift
//  Kotek
//
//  Entry screen (PRD §8), built to the Kotek design: the wordmark over the
//  drifting pattern, the account choice, and the gangsa table along the foot
//  (`LaunchStage`, shared with the splash). Behind it, as behind every
//  screen, the row of carved leaves running right (`PatternBackground`).
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

    var body: some View {
        GeometryReader { _ in
            ZStack {
                LaunchStage(animated: !app.splashCovering) {
                    if app.account == nil {
                        accountChoice
                    } else {
                        AppButton(
                            title: "Get started",
                            prominence: .primary,
                            size: .large
                        ) {
                            music.stop()
                            app.begin()
                        }
                        .fixedSize()
                    }
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
                    app.accountError = String(localized: "Couldn't sign in with Apple. Try again.")
                }

                AppButton(title: "Continue as guest", size: .large) {
                    music.stop()
                    app.continueAsGuest()
                }
                .fixedSize()
            }

            Text(app.accountError ?? String(localized: "As a guest, your progress stays on this iPhone only."))
                .font(.sans(12))
                .foregroundStyle(app.accountError == nil ? Theme.cream.opacity(0.62) : Theme.miss)
        }
    }

    // MARK: - Corner Affordances

    private func cornerButton(
        _ label: LocalizedStringKey,
        hint: LocalizedStringKey,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> some View
    ) -> some View {
        Button(action: action) {
            content()
                .appControlSurface(size: .regular, shape: .capsule, prominence: .secondary)
        }
        .buttonStyle(.appPlain)
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
        AppIconButton(systemImage: "questionmark", label: "How Kotek works") {
            app.openOnboarding()
        }
        .accessibilityHint("Replays the introduction")
    }
}

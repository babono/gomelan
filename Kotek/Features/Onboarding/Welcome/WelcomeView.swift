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

                    Spacer().frame(height: h * 0.07)

                    PillButton(
                        title: "Get started",
                        trailingSystemImage: "arrow.right",
                        style: .filled
                    ) {
                        music.stop()
                        app.begin()
                    }
                    .fixedSize()

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

    // MARK: - Corner Affordances

    private func cornerButton<V: View>(
        _ label: String,
        hint: String,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> V
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

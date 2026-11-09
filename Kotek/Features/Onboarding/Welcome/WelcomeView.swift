//
//  WelcomeView.swift
//  Kotek
//
//  Entry screen (PRD §8), in the November 2026 redesign: on paper, inside
//  the open gate the splash has just swung back (`PuraGate`, drawn here too,
//  in the same place, so the splash can leave without anything moving), the
//  red wordmark and its script, the account choice, a penjor arching in from
//  each post (`Penjor`), and the gangsa playing along the foot.
//
//  The first screen of the redesign to land, so it paints its own paper over
//  the app's brown ground (`PatternBackground`, in RootView) rather than
//  changing that for every screen. When the rest move over, this goes.
//

import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var app
    @State private var music = TitleMusic()
    /// Lives here rather than with the splash screen it belongs to, because
    /// this is the one place in launch where starting a sound is known to
    /// work — the music bed has always been audible from here. See SplashChime.
    @State private var chime = SplashChime()
    /// The penjor's easter egg — see `HangTilt`.
    @State private var tilt = HangTilt()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where the gamelan bed sits while the opening kempur is ringing.
    private static let duckedMusicLevel: Float = 0.4

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let u = LaunchLayout.unit(in: size)
            // The mockup's 1x — unless that would reach the gate. It must
            // stand INSIDE it: on an iPad the layout is taller for its width
            // (PadScale), the 1x gangsa came out wider than the opening, its
            // horns hidden behind the splash's walls during the approach and
            // then drawn over the gate once the splash had gone — a blink of
            // the two swapping places.
            let table = min(474 * u, PuraGate.openingWidth(in: size) - 2 * 16 * u)
            // The camera, while the splash walks up to its gate — see `zoom`.
            let z = zoom
            // The wordmark and the account choice sit centred in the paper
            // above the gangsa's frame. The mockup put them a little high on a
            // phone, and on an iPad — where the gangsa is narrower than its
            // 1x to fit the gate — a lot high.
            let block = Self.wordmarkHeight * u + Self.choiceGap * u + choiceHeight
            let top = max(0, (size.height - GangsaTable.frameHeight(for: table) - block) / 2)

            ZStack(alignment: .top) {
                Theme.paper
                // Behind the gate: their feet stand behind its posts.
                Penjor(side: -1, zoom: z, swingPeriod: 3.4, tilt: tilt)
                Penjor(side: 1, zoom: z, swingPeriod: 3.9, tilt: tilt)
                // Only once the splash's gate has finished opening over it —
                // see `AppState.splashGateOpen`.
                if app.splashGateOpen {
                    PuraGate(progress: 1)
                }

                VStack(spacing: 0) {
                    wordmark(u: u * z)
                    Group {
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
                    .padding(.top, Self.choiceGap * u * z)
                    .arrivesWithCamera(app.splashGateOpen)
                }
                // Where the camera sees the top of the block: about the middle
                // of the bottom edge, like the gate.
                .padding(.top, size.height - (size.height - top) * z)

                // Held still while the splash covers it: it is a pure function
                // of the clock, so it starts on the right frame wherever that is.
                //
                // Laid out at full size and SCALED to the camera, about the
                // middle of its foot — unlike the rest of this screen (see
                // `zoom`). Sized from the zoom, it skewed right through the
                // approach: a GeometryReader inside lays its keys and frame
                // out at the NEW size at once, while only the reader's own
                // frame animates, so the full-size table was drawn from the
                // small one's top-left corner and slid back into place. It
                // has no glass and no UIKit in it, which is what kept the
                // rest of the screen off `scaleEffect`.
                GangsaTable(animated: !app.splashCovering)
                    .frame(width: table, height: GangsaTable.height(for: table))
                    .scaleEffect(z, anchor: .bottom)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                // Corner affordance: help. Inside the open gate's post, not
                // over it. (The Mekar Bhuana colophon beside it was taken out.)
                HStack(spacing: 2) {
                    Spacer()
                    howItWorks
                }
                .padding(.top, 14)
                .padding(.trailing, 86 * u + 8)
                .arrivesWithCamera(app.splashGateOpen)
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
            music.setLevel(app.musicHushed ? 0 : 1.0, fadeDuration: 1.8)
        }
        // Down quickly for the onboarding's sample, back slowly after it.
        .onChange(of: app.musicHushed) { _, hushed in
            music.setLevel(hushed ? 0 : 1.0, fadeDuration: hushed ? 0.3 : 1.5)
        }
        .onAppear { if !reduceMotion { tilt.start() } }
        .onDisappear {
            tilt.stop()
            music.stop()
            Task { @concurrent in
                await AudioSessionManager.configure()
            }
        }
    }

    // MARK: - The approach

    /// How close the camera is. While the splash covers this screen it is
    /// drawn as if from a little way off, behind the splash's distant gate;
    /// `onOpen` lifts `splashCovering` inside the splash's opening animation,
    /// and the wordmark and the gangsa grow with the gate in that same
    /// transaction.
    ///
    /// Done in LAYOUT — the sizes and the top padding are worked out from the
    /// zoom — not with a `scaleEffect` over the screen, which was the first
    /// version. Liquid Glass and the UIKit-drawn Sign in with Apple button do
    /// not follow a SwiftUI scale frame by frame: they were drawn stale
    /// through the approach and snapped into place the moment it ended, a
    /// visible jump in the last frame. The controls take no part in the
    /// approach at all; they arrive with the camera (`arrivesWithCamera`).
    private var zoom: CGFloat {
        app.splashCovering ? PuraGate.farZoom : 1
    }

    /// The wordmark and its script: 37 + 17 + 46 in the mockup.
    private static let wordmarkHeight: CGFloat = 100
    /// From the script to the buttons, in the mockup.
    private static let choiceGap: CGFloat = 14

    /// The buttons and the line under them, for centring the block. Controls
    /// are not scaled, so this is in points.
    private var choiceHeight: CGFloat {
        app.account == nil ? Theme.buttonHeight + 8 + 8 + 16 : Theme.buttonHeight
    }

    // MARK: - Wordmark

    /// KOTEK in red, and its name in Balinese script beneath — both at the
    /// mockup's 1x size (159 x 37 and 137 x 46), 17pt apart, times `u`.
    private func wordmark(u: CGFloat) -> some View {
        VStack(spacing: 17 * u) {
            // `wordmark-`, NOT `logo-kotek`: the app icon already claims
            // `logo-kotek`, and an asset catalog will compile two unrelated
            // things under one name and leave `Image` to pick between them.
            Image("wordmark-kotek-red")
                .resizable()
                .frame(width: 159 * u, height: 37 * u)
            Image("wordmark-kotek-script")
                .resizable()
                .frame(width: 137 * u, height: 46 * u)
        }
        // One element: two undescribed images in a row is worse than the name.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kotek")
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

                // The outlined button beside Apple's black one: two doors,
                // told apart at a glance. It was a charcoal pill while Apple's
                // was white; with Apple black (the design system's), two dark
                // pills read as one wide one.
                AppButton(title: "Continue as guest", size: .large) {
                    music.stop()
                    app.continueAsGuest()
                }
                .fixedSize()
            }

            Text(app.accountError ?? String(localized: "As a guest, your progress stays on this iPhone only."))
                .font(.sans(13))
                .foregroundStyle(app.accountError == nil ? Theme.paperText : Theme.miss)
                .padding(.top, 8)
        }
    }

    // MARK: - Corner Affordances

    private var howItWorks: some View {
        AppIconButton(systemImage: "questionmark", label: "How Kotek works") {
            app.openOnboarding()
        }
        .accessibilityHint("Replays the introduction")
    }
}

private extension View {
    /// Hidden, and out of reach, until the splash's camera has arrived; then
    /// a short fade in.
    func arrivesWithCamera(_ arrived: Bool) -> some View {
        opacity(arrived ? 1 : 0)
            .allowsHitTesting(arrived)
            .animation(.easeInOut(duration: 0.5), value: arrived)
    }
}

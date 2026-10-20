//
//  ProfileSetupView.swift
//  Kotek
//
//  The one step after a first Apple sign-in: a name and an avatar. Also the
//  "Edit profile" screen from Settings. Guests never see it — they have no
//  account to hang a profile on.
//
//  Skippable, because sign-in is never a wall: skipping keeps whatever name
//  Apple sent and deals an avatar at random, so the step is still done and
//  does not come back on the next launch.
//

import SwiftUI

struct ProfileSetupView: View {
    @Environment(AppState.self) private var app

    @State private var name = ""
    @State private var avatar: Avatar = .wayang
    @FocusState private var nameFocused: Bool

    private static let maxNameLength = 24
    private let columns = Array(repeating: GridItem(.fixed(64), spacing: 14), count: 5)

    /// Opened from Settings rather than straight after signing in.
    private var isEditing: Bool {
        app.profileReturn == .settings && app.playerAvatar != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                title: isEditing ? "Edit profile" : "Your profile",
                backTitle: isEditing ? "Cancel" : nil,
                onBack: isEditing ? { app.closeProfileSetup() } : nil
            )

            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    AvatarView(avatar: avatar, size: 120)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Your name")
                            .font(.sans(13, weight: .medium))
                            .textCase(.uppercase)
                            .tracking(1.5)
                            .foregroundStyle(Theme.stone)

                        TextField("Name", text: $name)
                            .textFieldStyle(.plain)
                            .font(.serif(24))
                            .foregroundStyle(Theme.cream)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .autocorrectionDisabled()
                            .textContentType(.nickname)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .frame(maxWidth: 300, alignment: .leading)
                            .background(Theme.deep.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.radius))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radius)
                                    .strokeBorder(
                                        nameFocused ? Theme.buttonFill : Theme.cream.opacity(0.15),
                                        lineWidth: nameFocused ? 2 : 1
                                    )
                            )
                            .onSubmit { nameFocused = false }
                            .onChange(of: name) { _, new in
                                if new.count > Self.maxNameLength {
                                    name = String(new.prefix(Self.maxNameLength))
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 32)

                Rectangle()
                    .fill(Theme.cream.opacity(0.15))
                    .frame(width: 1, height: 220)

                VStack(spacing: 20) {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Avatar.allCases) { option in
                            avatarButton(option)
                        }
                    }

                    if let error = app.accountError {
                        Text(error)
                            .font(.sans(13))
                            .foregroundStyle(Theme.miss)
                    }

                    HStack(spacing: 18) {
                        if !isEditing {
                            AppButton(title: "Skip", size: .large) { skip() }
                                .fixedSize()
                        }

                        AppButton(
                            title: isEditing ? "Save" : "Continue",
                            prominence: .primary,
                            size: .large
                        ) {
                            nameFocused = false
                            Task {
                                if await app.savePlayer(name: name, avatar: avatar) {
                                    app.closeProfileSetup()
                                }
                            }
                        }
                        .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.leading, 32)
            }
            .padding(.horizontal, 40)
            .frame(maxHeight: .infinity)
        }
        // The landscape keyboard covers most of the screen and a plain text
        // field has no Done key of its own. Tapping the screen is the escape.
        .contentShape(Rectangle())
        .onTapGesture { nameFocused = false }
        .onAppear {
            name = app.playerName ?? ""
            avatar = app.playerAvatar ?? Avatar.allCases.randomElement() ?? .wayang
        }
    }

    private func avatarButton(_ option: Avatar) -> some View {
        Button {
            avatar = option
        } label: {
            AvatarView(avatar: option, size: 64)
                .overlay(
                    Circle().strokeBorder(Theme.buttonFill, lineWidth: option == avatar ? 3 : 0)
                        .padding(-4)
                )
                .opacity(option == avatar ? 1 : 0.8)
        }
        .buttonStyle(.appPlain)
        .accessibilityAddTraits(option == avatar ? .isSelected : [])
    }

    /// Still saves: the step is done once an avatar exists, and Apple's name
    /// (already in the field) is kept. If it cannot reach the server, it moves
    /// on anyway — the step simply comes back after the next sign-in.
    private func skip() {
        nameFocused = false
        Task {
            _ = await app.savePlayer(name: name, avatar: avatar)
            app.closeProfileSetup()
        }
    }
}

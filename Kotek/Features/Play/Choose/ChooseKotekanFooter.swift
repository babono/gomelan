//
//  ChooseKotekanFooter.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// Bottom footer on the Kotekan selection carousel hosting the mute toggle,
/// swipe instruction caption, and Start button.
struct ChooseKotekanFooter: View {
    @Binding var muted: Bool
    let current: Kotekan?
    let playable: Bool
    /// One Start: the screen it opens (waterfall or camera top view) is
    /// `AppState.topView`'s choice, set in Settings, not a second button here.
    let onStart: (Kotekan) -> Void
    /// Only offered on the player's own figures; the built-ins are the app's.
    let onEdit: (Kotekan) -> Void
    let onDelete: (Kotekan) -> Void
    /// Two players, one screen (§6.6.3). Its own setup screen checks the
    /// figure fits both gangsa; here it only has to fit this one.
    let onCoop: (Kotekan) -> Void

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 14) {
                AppButton(
                    title: muted ? "Muted" : "Playing",
                    systemImage: muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    size: .regular
                ) {
                    muted.toggle()
                }
                .accessibilityLabel(muted ? "Unmute the preview" : "Mute the preview")

                Spacer()

                Text("Swipe to hear another")
                    .font(.sans(13))
                    .foregroundStyle(Theme.cream.opacity(0.45))

                Spacer()

                if let current, current.source != .builtin {
                    AppIconButton(systemImage: "trash", label: "Delete \(current.name)", size: .regular) {
                        onDelete(current)
                    }

                    AppButton(title: "Edit", size: .regular) {
                        onEdit(current)
                    }
                }

                // Nothing to start when a search matches nothing; Create is up top.
                if let current {
                    AppButton(title: "Coop", systemImage: "person.2.fill", size: .regular) {
                        onCoop(current)
                    }
                    .disabled(!playable)

                    AppButton(
                        title: "Start",
                        prominence: .primary,
                        size: .regular
                    ) {
                        onStart(current)
                    }
                    .disabled(!playable)
                }
            }
        }
        .padding(.bottom, 10)
    }
}

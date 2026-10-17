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
        HStack(spacing: 14) {
            Button {
                muted.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.symbol(13, weight: .semibold))
                    Text(muted ? "Muted" : "Playing")
                        .font(.sans(13, weight: .medium))
                }
                .foregroundStyle(muted ? Theme.cream.opacity(0.5) : Theme.gold)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .tintedButton()
                .contentShape(Capsule())
            }
            .buttonStyle(.kajar)
            .accessibilityLabel(muted ? "Unmute the preview" : "Mute the preview")

            Spacer()

            Text("Swipe to hear another")
                .font(.sans(13))
                .foregroundStyle(Theme.cream.opacity(0.45))

            Spacer()

            if let current, current.source != .builtin {
                Button {
                    onDelete(current)
                } label: {
                    Image(systemName: "trash")
                        .font(.symbol(14, weight: .semibold))
                        .foregroundStyle(Theme.cream.opacity(0.7))
                        .frame(width: 38, height: 38)
                        .tintedButton(in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.kajar)
                .accessibilityLabel("Delete \(current.name)")

                PillButton(title: "Edit", style: .outlined, compact: true) {
                    onEdit(current)
                }
            }

            // Nothing to start when a search matches nothing; Create is up top.
            if let current {
                PillButton(title: "Coop", systemImage: "person.2.fill", style: .outlined, compact: true) {
                    onCoop(current)
                }
                .disabled(!playable)
                .opacity(playable ? 1 : 0.4)

                PillButton(
                    title: "Start",
                    style: .filled,
                    compact: true
                ) {
                    onStart(current)
                }
                .disabled(!playable)
                .opacity(playable ? 1 : 0.4)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 10)
    }
}

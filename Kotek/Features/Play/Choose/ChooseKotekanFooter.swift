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
    let onStart: (Kotekan) -> Void

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
                .overlay(Capsule().strokeBorder(Theme.cream.opacity(0.22), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.kajar)
            .accessibilityLabel(muted ? "Unmute the preview" : "Mute the preview")

            Spacer()

            Text("Swipe to hear another")
                .font(.sans(13))
                .foregroundStyle(Theme.cream.opacity(0.45))

            Spacer()

            if let current {
                PillButton(
                    title: "Start",
                    trailingSystemImage: "arrow.right",
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

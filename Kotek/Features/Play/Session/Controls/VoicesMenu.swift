//
//  VoicesMenu.swift
//  Kotek
//
//  The practice screen's voices: your half sounded as a guide, and the
//  partner's half. One chip with a menu, next to the tempo, so both change
//  without stopping.
//
//  They were switches in Settings, which meant leaving the session to change
//  them, and they are exactly what changes mid-practice: the guide goes once
//  the figure is in your hands, the partner comes in once it is steady. One
//  menu rather than two chips because the top bar has no room for two on a
//  phone — their labels wrapped letter by letter.
//

import SwiftUI

struct VoicesMenu: View {
    @Binding var guide: Bool
    @Binding var partner: Bool

    var body: some View {
        Menu {
            Toggle("Guide · your half", isOn: $guide)
            Toggle("Partner · other half", isOn: $partner)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: guide || partner ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.symbol(12, weight: .semibold))
                Text("Voices")
                    .font(.sans(12, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.symbol(9, weight: .semibold))
            }
            .foregroundStyle(Theme.copper)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .overlay(
                Capsule().strokeBorder(Theme.copper.opacity(0.45), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .compositingGroup()
        .menuOrder(.fixed)
        .kajarOnChange(of: guide)
        .kajarOnChange(of: partner)
        .accessibilityLabel("Voices, guide \(guide ? "on" : "off"), partner \(partner ? "on" : "off")")
    }
}

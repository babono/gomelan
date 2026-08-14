//
//  ChooseKotekanView.swift
//  gomelan
//
//  Pick the interlocking figure to learn, and how many times around the gong
//  cycle to play it. Figures that need more bilah than the calibrated instrument
//  has are greyed out and unselectable (§4 Flow B).
//

import SwiftUI

struct ChooseKotekanView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Choose your kotekan",
                   backTitle: "Instruments",
                   onBack: { app.openChooseInstrument() },
                   trailingText: app.profile.name,
                   settingsAction: { app.openSettings() })

            HStack(alignment: .top, spacing: 16) {
                ForEach(app.kotekans) { k in
                    let playable = app.kotekan(k, playableOn: app.profile)
                    KotekanCard(kotekan: k, playable: playable)
                        .onTapGesture {
                            if playable {
                                app.chooseKotekan(k)
                            }
                        }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxHeight: .infinity)
        }
        .background(Theme.cream)
    }
}

private struct KotekanCard: View {
    let kotekan: Kotekan
    let playable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Level \(kotekan.level) · \(kotekan.toneLabel)", color: Theme.terracotta)

            Text(kotekan.name)
                .font(.serif(24))
                .foregroundStyle(Theme.charcoal)

            Text(kotekan.blurb)
                .font(.sans(14))
                .foregroundStyle(Theme.stone)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if !playable {
                Label("Needs \(kotekan.requiredKeys) keys", systemImage: "lock")
                    .font(.sans(12, weight: .medium))
                    .foregroundStyle(Theme.miss)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.creamSunken))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.charcoal.opacity(0.15), lineWidth: 1)
        )
        .opacity(playable ? 1 : 0.45)
    }
}

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

    @State private var selectedID: String?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Choose your kotekan",
                   backTitle: "Instruments",
                   onBack: { app.openChooseInstrument() },
                   trailingText: app.profile.name,
                   settingsAction: { app.openSettings() })

            HStack(alignment: .top, spacing: 16) {
                ForEach(app.kotekans) { k in
                    KotekanCard(kotekan: k,
                                selected: selectedID == k.id,
                                playable: app.kotekan(k, playableOn: app.profile))
                        .onTapGesture {
                            if app.kotekan(k, playableOn: app.profile) {
                                selectedID = k.id
                                app.chooseKotekan(k)
                            }
                        }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxHeight: .infinity)

            footer
        }
        .onAppear {
            if selectedID == nil {
                selectedID = app.kotekans.first(where: { app.kotekan($0, playableOn: app.profile) })?.id
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if let selected = app.kotekans.first(where: { $0.id == selectedID }) {
                Text(selected.name)
                    .font(.serif(18, weight: .bold))
                    .foregroundStyle(Theme.charcoal)
                Text("· Level \(selected.level) (\(selected.toneLabel))")
                    .font(.sans(14))
                    .foregroundStyle(Theme.stone)
            }

            Spacer()

            PillButton(title: "Next", style: .outlined) {
                if let k = app.kotekans.first(where: { $0.id == selectedID }) {
                    app.chooseKotekan(k)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Theme.charcoal.opacity(0.12)).frame(height: 1) }
    }
}

private struct KotekanCard: View {
    let kotekan: Kotekan
    let selected: Bool
    let playable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Level \(kotekan.level) · \(kotekan.toneLabel)",
                         color: selected ? Theme.terracotta : Theme.stone)

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
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.creamSunken : .clear))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Theme.terracotta : Theme.charcoal.opacity(0.2),
                              lineWidth: selected ? 1.5 : 1)
        )
        .opacity(playable ? 1 : 0.45)
    }
}

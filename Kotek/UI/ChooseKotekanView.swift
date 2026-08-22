//
//  ChooseKotekanView.swift
//  Kotek
//
//  Pick the interlocking figure to learn. Tapping a card goes straight to the
//  count-in — this is the last decision before playing, and the only one left:
//  which half you take is a toggle on the practice screen, and how many times
//  around has no answer, because it goes around until you stop it.
//
//  Figures that need more bilah than the calibrated gangsa has are greyed out
//  and unselectable (§4 Flow B).
//

import SwiftUI

struct ChooseKotekanView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Choose your kotekan",
                   onBack: { app.openChooseInstrument() },
                   settingsAction: { app.openSettings() })

            HStack(alignment: .top, spacing: 16) {
                ForEach(app.kotekans) { k in
                    let playable = app.kotekan(k, playableOn: app.profile)
                    KotekanCard(kotekan: k, playable: playable,
                                record: app.profile.bestRecord(kotekanId: k.id))
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
    }
}

private struct KotekanCard: View {
    let kotekan: Kotekan
    let playable: Bool
    /// Your best on this figure, whichever half and speed it was set at — the
    /// conditions come with it, so a 0.75× best is never read as a full-tempo
    /// one. nil until eight consecutive cycles have been played.
    let record: PatternRecord?

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
            } else if let record {
                HStack(spacing: 6) {
                    Image(systemName: "trophy")
                        .font(.symbol(11, weight: .semibold))
                    Text(String(format: "%.0f%%", record.accuracy * 100))
                        .font(.sans(13, weight: .semibold))
                    Text("\(record.half.capitalized) · \(Theme.tempoLabel(record.tempo))")
                        .font(.sans(12))
                        .foregroundStyle(Theme.stone)
                }
                .foregroundStyle(Theme.terracotta)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.deep.opacity(0.78)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.charcoal.opacity(0.15), lineWidth: 1)
        )
        .opacity(playable ? 1 : 0.45)
    }
}

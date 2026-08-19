//
//  ChooseHalfView.swift
//  gomelan
//
//  A kotekan is shared between two players: polos on the beat, sangsih off it.
//  Here the learner picks the half they'll play. Polos is the gentler start, so
//  it's selected by default — it serves the "fear of being wrong" barrier (§5.3).
//

import SwiftUI

struct ChooseHalfView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if let k = app.selectedKotekan {
            VStack(spacing: 0) {
                TopBar(title: "Which half will you play?",
                       backTitle: "Back",
                       onBack: { app.backToKotekan() },
                       trailingText: k.name)

                HStack(spacing: 16) {
                    HalfCard(half: .polos, kotekan: k)
                        .onTapGesture {
                            app.chooseHalf(.polos)
                        }
                    HalfCard(half: .sangsih, kotekan: k)
                        .onTapGesture {
                            app.chooseHalf(.sangsih)
                        }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxHeight: .infinity)
            }
        } else {
            Color.clear.onAppear { app.backToKotekan() }
        }
    }
}

private struct HalfCard: View {
    let half: KotekanHalf
    let kotekan: Kotekan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(half.eyebrow, color: Theme.terracotta)

            Text(half.title)
                .font(.serif(42))
                .foregroundStyle(Theme.charcoal)

            Text(half.blurb)
                .font(.sans(14))
                .foregroundStyle(Theme.stone)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Text("plays \(kotekan.strokeCount(half)) of \(kotekan.slotsPerCycle) strokes")
                .font(.sans(14, weight: .medium))
                .foregroundStyle(Theme.terracotta)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.deep.opacity(0.78)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.charcoal.opacity(0.15), lineWidth: 1)
        )
    }
}

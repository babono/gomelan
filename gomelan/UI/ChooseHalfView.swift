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

    @State private var half: KotekanHalf = .polos

    var body: some View {
        if let k = app.selectedKotekan {
            VStack(spacing: 0) {
                TopBar(title: "Which half will you play?",
                       backTitle: "Back",
                       onBack: { app.backToKotekan() },
                       trailingText: k.name)

                HStack(spacing: 16) {
                    HalfCard(half: .polos, kotekan: k, selected: half == .polos)
                        .onTapGesture { half = .polos }
                    HalfCard(half: .sangsih, kotekan: k, selected: half == .sangsih)
                        .onTapGesture { half = .sangsih }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxHeight: .infinity)

                HStack {
                    Spacer()
                    PillButton(title: "Start practice", style: .outlined) {
                        app.startSession(half: half)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
            }
            .onAppear { half = app.chosenHalf }
        } else {
            Color.clear.onAppear { app.backToKotekan() }
        }
    }
}

private struct HalfCard: View {
    let half: KotekanHalf
    let kotekan: Kotekan
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(half.eyebrow, color: selected ? Theme.terracotta : Theme.stone)

            Text(half.title)
                .font(.serif(42))
                .foregroundStyle(Theme.charcoal)

            Text(half.blurb)
                .font(.sans(14))
                .foregroundStyle(Theme.stone)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Text("plays \(kotekan.strokeCount(half)) of \(Kotekan.strokesPerCycle) strokes")
                .font(.sans(14, weight: .medium))
                .foregroundStyle(selected ? Theme.terracotta : Theme.stone)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.creamSunken : .clear))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Theme.terracotta : Theme.charcoal.opacity(0.2),
                              lineWidth: selected ? 1.5 : 1)
        )
    }
}

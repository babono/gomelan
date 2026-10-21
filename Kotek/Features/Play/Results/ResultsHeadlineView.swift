//
//  ResultsHeadlineView.swift
//  Kotek
//
//  The headline percentage for the results screen.
//

import SwiftUI

struct ResultsHeadlineView: View {
    let result: SongResult

    /// Just the overall percentage — the on-beat share of the whole session.
    /// The wrong-bilah and missed counts that sat under it were taken out: the
    /// graph is in percentages too, and three counts beside one percentage
    /// were a second scale to read. They are still filed (`PracticeSession`).
    var body: some View {
        overall
    }

    private var overall: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(Int((result.onBeatFraction * 100).rounded()))%")
                .font(.serif(52))
                .foregroundStyle(Theme.gold)
            SectionLabel("Overall", color: Theme.stone)
        }
        .accessibilityElement(children: .combine)
    }
}

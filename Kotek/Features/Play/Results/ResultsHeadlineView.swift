//
//  ResultsHeadlineView.swift
//  Kotek
//
//  The headline counts for the results screen.
//

import SwiftUI

struct ResultsHeadlineView: View {
    let result: SongResult

    /// R The accuracy percentage and the record line under it were taken out:
    /// R the graph below now says WHERE it went wrong, and a single percentage
    /// R above it competed with that for the first look without telling the
    /// R player what to practise. Records are still kept (`PracticeSession`) —
    /// R they are just not this screen's headline any more.
    ///
    /// An overall percentage is back, but as the first of the counts rather
    /// than a headline over the graph, so it gives one number to go by
    /// without competing with the graph for the first look. It is the on-beat
    /// share of the whole session — the same span as the three counts beside
    /// it, so it always agrees with them — not the best window the record is
    /// kept on.
    var body: some View {
        // R The same three counts `practice_session` files, over the same
        // R span — the whole session — rather than the best window's tallies.
        // R The window's "mistakes" lumped wrong bars in with misses, and a
        // R screen that disagrees with the history it just wrote is a bug
        // R report waiting to happen.
        VStack(alignment: .leading, spacing: 14) {
            overall
            HStack(alignment: .top, spacing: 24) {
                stat("On the beat", "\(result.onBeatCount)")
                stat("Wrong bilah", "\(result.wrongKeyCount)")
                stat("Missed", "\(result.missedCount)")
            }
        }
    }

    /// Larger and in gold, on its own line: it summarises the counts under
    /// it, so it should not read as a fourth one beside them.
    private var overall: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(Int((result.onBeatFraction * 100).rounded()))%")
                .font(.serif(52))
                .foregroundStyle(Theme.gold)
            SectionLabel("Overall", color: Theme.stone)
        }
        .accessibilityElement(children: .combine)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(label, color: Theme.stone)
                .lineLimit(1)
                .fixedSize()
            Text(value)
                .font(.serif(28))
                .foregroundStyle(Theme.charcoal)
        }
    }
}

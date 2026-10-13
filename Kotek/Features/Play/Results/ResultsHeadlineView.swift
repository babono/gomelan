//
//  ResultsHeadlineView.swift
//  Kotek
//
//  The headline counts for the results screen.
//

import SwiftUI

struct ResultsHeadlineView: View {
    let result: SongResult

    // R The accuracy percentage and the record line under it were taken out:
    // R the graph below now says WHERE it went wrong, and a single percentage
    // R above it competed with that for the first look without telling the
    // R player what to practise. Records are still kept (`PracticeSession`) —
    // R they are just not this screen's headline any more.
    var body: some View {
        // R The same three counts `practice_session` files, over the same
        // R span — the whole session — rather than the best window's tallies.
        // R The window's "mistakes" lumped wrong bars in with misses, and a
        // R screen that disagrees with the history it just wrote is a bug
        // R report waiting to happen.
        HStack(alignment: .top, spacing: 24) {
            stat("On the beat", "\(result.onBeatCount)")
            stat("Wrong bilah", "\(result.wrongKeyCount)")
            stat("Missed", "\(result.missedCount)")
        }
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

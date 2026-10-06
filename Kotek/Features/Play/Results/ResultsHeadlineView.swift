//
//  ResultsHeadlineView.swift
//  Kotek
//
//  The headline numbers and record status for the results screen.
//

import SwiftUI

struct ResultsHeadlineView: View {
    @Environment(AppState.self) private var app

    let best: ScoringWindow
    let result: SongResult

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Accuracy", color: Theme.stone)
                Text(String(format: "%.2f%%", best.accuracy * 100))
                    .font(.serif(46))
                    .foregroundStyle(Theme.charcoal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                recordLine
            }

            VStack(alignment: .leading, spacing: 10) {
                stat("On the beat", "\(best.onBeat)")
                stat("Mistakes", "\(best.mistakes)")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// What this session did to the figure's record.
    ///
    /// Records need a FULL eight-cycle window, so a short session says so
    /// rather than silently not counting.
    @ViewBuilder
    private var recordLine: some View {
        if result.cycles.count < SongResult.scoringWindow {
            label("Needs \(SongResult.scoringWindow) cycles to set a record", Theme.stone)
        } else if app.lastSetRecord, let previous = app.previousRecord {
            label(String(format: "New record · was %.1f%%", previous * 100), Theme.hit)
        } else if app.lastSetRecord {
            label("First record on this gangsa", Theme.hit)
        } else if let best = currentRecord {
            label(String(format: "Your best is %.1f%%", best * 100), Theme.stone)
        }
    }

    /// The record as it stands NOW — which, if this session beat it, is this
    /// session's own score. Only read on the path where it did not.
    private var currentRecord: Double? {
        guard let k = app.selectedKotekan else { return nil }
        return app.profile.record(
            kotekanId: k.id,
            half: app.chosenHalf.rawValue,
            tempo: app.tempoScale
        )?.accuracy
    }

    private func label(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.sans(13, weight: .medium))
            .foregroundStyle(color)
            .padding(.top, 4)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(label, color: Theme.stone)
            Text(value)
                .font(.serif(22))
                .foregroundStyle(Theme.charcoal)
        }
    }
}

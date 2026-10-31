//
//  ResultsHeadlineView.swift
//  Kotek
//
//  The headline percentage for the results screen.
//

import SwiftUI

struct ResultsHeadlineView: View {
    let result: SongResult

    /// The overall percentage — the on-beat share of the whole session — then
    /// how many gong cycles and how long it was taken over, so 77% reads as
    /// 77% of twelve passes and four minutes, not of one. The wrong-bilah and missed counts that sat under
    /// it were taken out: the graph is in percentages too, and three counts
    /// beside one percentage were a second scale to read. They are still filed
    /// (`PracticeSession`).
    ///
    /// Three of them at full size outrun the column on a landscape phone, so
    /// the row steps down until it fits rather than wrapping.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(size: 52, spacing: 28)
            row(size: 40, spacing: 20)
            row(size: 30, spacing: 14)
        }
    }

    private func row(size: CGFloat, spacing: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            stat(Theme.percentLabel(result.onBeatFraction), label: "Overall", size: size)
            stat("\(result.cycles.count)", label: result.cycles.count == 1 ? "Cycle" : "Cycles", size: size)
            stat(Self.clock(result.practiceSeconds), label: "Practice", size: size)
        }
        .fixedSize()
    }

    /// "4:12", or "1:04:12" past the hour — as the kotekan cards show length.
    private static func clock(_ seconds: Double) -> String {
        let d = Duration.seconds(Int(seconds.rounded()))
        return d.formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    private func stat(_ value: String, label: LocalizedStringKey, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.2) {
            Text(value)
                .font(.serif(size))
                .foregroundStyle(Theme.gold)
            SectionLabel(label, color: Theme.stone)
        }
        .accessibilityElement(children: .combine)
    }
}

//
//  MasteryProgressView.swift
//  Kotek
//
//  Where the session went on the gangsa's own ladder.
//  The one place the two halves of the app meet: accuracy is about this
//  session and forgets it the moment you leave, but landed notes accumulate on
//  the instrument for as long as you own it.
//

import SwiftUI

struct MasteryProgressView: View {
    let profile: InstrumentProfile
    /// The total before this session. nil on the paths that never credited one,
    /// in which case there is nothing to travel and the bar simply shows where
    /// it stands.
    let before: Int?
    let landed: Int

    @State private var shownFraction: Double = 0
    @State private var shownRank: Mastery.Rank = .paria
    @State private var shownNotes: Int = 0
    @State private var arrived = false

    private var startMastery: Mastery {
        Mastery(notesLanded: before ?? profile.notesLanded)
    }

    private var endMastery: Mastery {
        profile.mastery
    }

    private var promoted: Bool {
        endMastery.rank != startMastery.rank
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionLabel("Your gangsa", color: Theme.stone)
                Spacer()
                if landed > 0 {
                    Text("+\(landed.formatted()) landed")
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.hit)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(shownRank.title)
                    .font(.serif(24))
                    // The rung's own colour, and it changes mid-animation on a
                    // promotion — the name and the shade arrive together, which
                    // is most of what makes the second stage read as a step up
                    // rather than as a bar starting over.
                    .foregroundStyle(shownRank.color)
                Text(shownRank.gloss)
                    .font(.sans(14))
                    .foregroundStyle(Theme.stone)
                Spacer()
                if promoted, arrived {
                    Text("New rung")
                        .font(.sans(12, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(1.5)
                        .foregroundStyle(Theme.deep)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(shownRank.color, in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.charcoal.opacity(0.12))
                    Capsule()
                        .fill(shownRank.color)
                        .frame(width: max(4, geo.size.width * shownFraction))
                }
            }
            .frame(height: 7)

            Text(footnote)
                .font(.sans(13))
                .foregroundStyle(Theme.stone)
                .contentTransition(.numericText())
        }
        .onAppear(perform: run)
    }

    private var footnote: String {
        let m = Mastery(notesLanded: shownNotes)
        guard let next = m.next, let togo = m.notesToNext else {
            return "\(shownNotes.formatted()) notes landed on this gangsa — the ladder is finished"
        }
        return "\(shownNotes.formatted()) notes landed · \(togo.formatted()) to \(next.title)"
    }

    /// Start where the session started, then travel.
    ///
    /// A promotion is two moves, not one. Interpolating straight to the new
    /// rung's progress would run the bar BACKWARDS — 92% of Sudra to 4% of
    /// Waisya — which reads as losing ground at the exact moment you gained it.
    /// So the old rung fills to the end first, then the label changes and the
    /// new one fills from nothing.
    private func run() {
        shownRank = startMastery.rank
        shownFraction = startMastery.progress
        shownNotes = startMastery.notes

        guard before != nil, landed > 0 else {
            shownRank = endMastery.rank
            shownFraction = endMastery.progress
            shownNotes = endMastery.notes
            arrived = true
            return
        }

        guard promoted else {
            withAnimation(.easeOut(duration: 1.1).delay(0.25)) {
                shownFraction = endMastery.progress
                shownNotes = endMastery.notes
            }
            arrived = true
            return
        }

        withAnimation(.easeIn(duration: 0.55).delay(0.25)) { shownFraction = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            shownRank = endMastery.rank
            shownFraction = 0
            withAnimation(.easeOut(duration: 0.9)) {
                shownFraction = endMastery.progress
                shownNotes = endMastery.notes
            }
            withAnimation(.snappy(duration: 0.4).delay(0.2)) { arrived = true }
        }
    }
}

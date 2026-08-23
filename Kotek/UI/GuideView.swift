//
//  GuideView.swift
//  Kotek
//
//  What the app is and how the grade works, in one panel. Reached from the ⓘ on
//  the instrument picker, and shown once by itself the first time anybody opens
//  the app — see `AppState.hasSeenGuide`.
//
//  A CUSTOM overlay rather than `.sheet`. A system sheet on a landscape phone
//  arrives as a card with its own grabber, its own chrome and its own idea of
//  what a background is, in the middle of an app that is landscape-locked and
//  has spent a lot of effort on one warm ground with no light/dark flip in it.
//  This is a dimmed backdrop and a panel, which is all a sheet was going to be.
//
//  Two columns because the screen is a landscape phone: wide and short. A single
//  scrolling column would put the grade — the half people came here to read —
//  below the fold on every device.
//
//  It is metered to FIT, not to scroll. A landscape phone gives about 400pt of
//  height; the header and footer take a hundred of it, so the two columns have
//  roughly 250pt between them and every number below was chosen against that.
//  The first draft was written at a comfortable reading size and put four of the
//  five rungs under the fold, which is the same failure as a single column. The
//  ScrollView stays as a backstop for an SE and for large Dynamic Type — it
//  should not be doing anything on a normal phone. If you add a paragraph here,
//  take one out.
//

import SwiftUI

struct GuideView: View {
    var onClose: () -> Void

    var body: some View {
        ZStack {
            // Tapping outside closes. The panel swallows its own taps so a
            // stray touch while reading the table does not dismiss it.
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            panel
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
        }
        .transition(.opacity)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                HStack(alignment: .top, spacing: 30) {
                    concept.frame(maxWidth: .infinity, alignment: .leading)

                    Rectangle().fill(Theme.cream.opacity(0.12)).frame(width: 1)

                    grade.frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 26)
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
        }
        .background(Theme.deep, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Theme.cream.opacity(0.12), lineWidth: 1)
        )
        .frame(maxWidth: 900)
    }

    // MARK: - Chrome

    /// Title and dismiss on ONE row, and the dismiss is the button rather than
    /// an ✕ with a "Got it" underneath the content.
    ///
    /// A footer bar cost about 55pt of a panel that only ever had ~290 to
    /// spend, and it spent it at the bottom — where the last two rungs of the
    /// grade were. One row does both jobs: the pill is a far bigger target than
    /// a corner glyph, and the backdrop closes on a tap as well, so nobody is
    /// hunting for the way out.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("How Gomelan works")
                .font(.serif(24))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Theme.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 16)

            PillButton(title: "Got it", style: .filled, compact: true, action: onClose)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 8 }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    // MARK: - The idea

    private var concept: some View {
        //R Every line here is cut to about 145 characters, which is three lines
        //R in a column this wide. It is not a style: three blocks at four lines
        //R each overruns the 227pt these columns actually get, and the overrun
        //R lands on the grade table, which is the half people opened this for.
        VStack(alignment: .leading, spacing: 10) {
            block("The rig",
                  "Your phone sits on a stand above the gangsa. The camera sees which key you strike; the mic hears when. The next key lights up on the instrument.")

            block("Kotekan",
                  "Two players share a figure: polos on the beat, sangsih between. You take a half, the app plays the other. Swap sides any time.")

            block("Practice",
                  "The figure loops until you end it. Nothing fails. Your score is your best eight cycles in a row — that is what sets a record.")
        }
    }

    private func block(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title, color: Theme.gold)
            Text(body)
                .font(.sans(13))
                .foregroundStyle(Theme.cream.opacity(0.75))
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The grade

    private var grade: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Your gangsa's grade", color: Theme.gold)

            Text("Notes that land — right key, near enough the beat — build the grade of the gangsa you played them on. It only ever goes up.")
                .font(.sans(13))
                .foregroundStyle(Theme.cream.opacity(0.75))
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                //R Reversed: highest first. A ladder is read top-down, and the
                //R rung worth showing off belongs at the top of it — the model
                //R stores them lowest-first because thresholds have to ascend.
                ForEach(Mastery.Rank.allCases.reversed(), id: \.self) { rank in
                    row(rank)
                    if rank != Mastery.Rank.allCases.first {
                        Rectangle().fill(Theme.cream.opacity(0.07)).frame(height: 1)
                    }
                }
            }
            .padding(.vertical, 3)
            .background(Theme.ground.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.radius))
        }
    }

    private func row(_ rank: Mastery.Rank) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(rank.color)
                .frame(width: 8, height: 18)

            //R Name and gloss on ONE line. Stacked, five rungs came to 200pt
            //R and pushed the bottom two off the panel — and a ladder with its
            //R top three visible is worse than no ladder, because it reads as
            //R the whole thing.
            Text(rank.title)
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(rank.color)
                .fixedSize()

            Text(rank.gloss)
                .font(.sans(11))
                .foregroundStyle(Theme.cream.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 6)

            Text(rank.threshold == 0 ? "from note one"
                                     : "\(rank.threshold.formatted())")
                .font(.sans(11, weight: .medium))
                .foregroundStyle(Theme.cream.opacity(0.62))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

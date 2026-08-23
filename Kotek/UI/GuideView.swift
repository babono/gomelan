//
//  GuideView.swift
//  Kotek
//
//  What the app is and how the grade works, in one panel. Reached from the help
//  button on the instrument picker, and shown once by itself the first time anybody opens
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
    let guide: AppState.Guide
    var onClose: () -> Void

    var body: some View {
        switch guide {
        case .app:
            GuidePanel(title: "How Gomelan works", onClose: onClose) {
                AppGuideConcept()
            } right: {
                AppGuideGrade()
            }
        case .kotekan:
            GuidePanel(title: "Kotekan", onClose: onClose) {
                KotekanGuideWeave()
            } right: {
                KotekanGuideLegend()
            }
        }
    }
}

/// The shell: dimmed backdrop, panel, title and dismiss on one row, two columns.
///
/// A CUSTOM overlay rather than `.sheet`. A system sheet on a landscape phone
/// arrives as a card with its own grabber, its own chrome and its own idea of
/// what a background is, in the middle of an app that is landscape-locked and
/// has spent a lot of effort on one warm ground with no light/dark flip in it.
/// This is a dimmed backdrop and a panel, which is all a sheet was going to be.
///
/// Two columns because the screen is a landscape phone: wide and short. A single
/// scrolling column would put half of every panel below the fold.
///
/// It is metered to FIT, not to scroll. A landscape phone gives about 400pt of
/// height; the header takes sixty of it, so the columns have roughly 290pt
/// between them and every number in here was chosen against that. The first
/// draft was written at a comfortable reading size and put four of five grade
/// rungs under the fold. The ScrollView stays as a backstop for an SE and for
/// large Dynamic Type — it should not be doing anything on a normal phone. If
/// you add a paragraph to a column, take one out.
struct GuidePanel<Left: View, Right: View>: View {
    let title: String
    var onClose: () -> Void
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        ZStack {
            // Tapping outside closes. The panel swallows its own taps so a
            // stray touch while reading does not dismiss it.
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
                    left.frame(maxWidth: .infinity, alignment: .leading)

                    Rectangle().fill(Theme.cream.opacity(0.12)).frame(width: 1)

                    right.frame(maxWidth: .infinity, alignment: .leading)
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

    /// Title and dismiss on ONE row, and the dismiss is the button rather than
    /// an ✕ with a "Got it" underneath the content.
    ///
    /// A footer bar cost about 55pt of a panel that only ever had ~290 to spend,
    /// and it spent it at the bottom — where the last two rungs of the grade
    /// table were. One row does both jobs: the pill is a far bigger target than
    /// a corner glyph, and the backdrop closes on a tap as well, so nobody is
    /// hunting for the way out.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
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
}

// MARK: - Shared column pieces

/// A titled paragraph. Every line in a guide column is cut to about 145
/// characters, which is three lines at this width — not a style, a budget: four
/// blocks at four lines each overruns the height these columns actually get.
struct GuideBlock: View {
    let heading: String
    let text: String

    init(_ heading: String, _ text: String) {
        self.heading = heading
        self.text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(heading, color: Theme.gold)
            Text(text)
                .font(.sans(13))
                .foregroundStyle(Theme.cream.opacity(0.75))
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The prose under a column heading, for columns whose heading is followed by
/// something other than more prose.
struct GuideLead: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.sans(13))
            .foregroundStyle(Theme.cream.opacity(0.75))
            .lineSpacing(1)
            .fixedSize(horizontal: false, vertical: true)
    }
}


// MARK: - "How Gomelan works"

private struct AppGuideConcept: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideBlock("The rig",
                       "Your phone sits on a stand above the gangsa. The camera sees which key you strike; the mic hears when. The next key lights up on the instrument.")

            GuideBlock("Kotekan",
                       "Two players share a figure: polos on the beat, sangsih between. You take a half, the app plays the other when you ask.")

            GuideBlock("Practice",
                       "The figure loops until you end it. Nothing fails. Your score is your best eight cycles in a row — that is what sets a record.")
        }
    }
}

private struct AppGuideGrade: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Your gangsa's grade", color: Theme.gold)

            GuideLead("Notes that land — right key, near enough the beat — build the grade of the gangsa you played them on. It only ever goes up.")

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

            Text(rank.threshold == 0 ? "from note one" : "\(rank.threshold.formatted())")
                .font(.sans(11, weight: .medium))
                .foregroundStyle(Theme.cream.opacity(0.62))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - "Kotekan"

private struct KotekanGuideWeave: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideBlock("One melody, two players",
                       "A kotekan is a line too fast to play alone, so it is split. Neither part is the tune. The tune is what you hear when both are going.")

            GuideBlock("Polos",
                       "The straight half. It lands on the beat with the kajar and holds the frame steady. This is the one to learn first.")

            GuideBlock("Sangsih",
                       "The answering half. It falls in the gaps polos leaves, off the beat — harder, and the reason the pair sounds twice as fast as either.")
        }
    }
}

private struct KotekanGuideLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Reading a card", color: Theme.gold)

            GuideLead("Each card draws its figure across one gong cycle: time runs left to right, and the keys go low to high up the side. Swipe to hear the next.")

            VStack(spacing: 0) {
                row(swatch: .single(Theme.polosVoice), "Polos", "on the beat")
                divider
                row(swatch: .single(Theme.sangsihVoice), "Sangsih", "between the beats")
                divider
                row(swatch: .split, "Both together", "the shared anchor tone")
                divider
                row(swatch: .line, "The sweep", "where the cycle is now")
            }
            .padding(.vertical, 3)
            .background(Theme.ground.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.radius))
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.cream.opacity(0.07)).frame(height: 1)
    }

    private enum Swatch {
        case single(Color)
        case split
        case line
    }

    private func row(swatch: Swatch, _ title: String, _ gloss: String) -> some View {
        HStack(spacing: 10) {
            Group {
                switch swatch {
                case .single(let color):
                    RoundedRectangle(cornerRadius: 2).fill(color)
                case .split:
                    // The same drawing the score uses: two halves of one block,
                    // because a stroke both parts play is one stroke.
                    HStack(spacing: 0) {
                        Rectangle().fill(Theme.polosVoice)
                        Rectangle().fill(Theme.sangsihVoice)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                case .line:
                    Rectangle().fill(Theme.cream.opacity(0.85)).frame(width: 2)
                }
            }
            .frame(width: 20, height: 14)

            Text(title)
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(Theme.cream)
                .fixedSize()

            Text(gloss)
                .font(.sans(11))
                .foregroundStyle(Theme.cream.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

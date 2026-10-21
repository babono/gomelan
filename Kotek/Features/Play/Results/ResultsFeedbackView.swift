//
//  ResultsFeedbackView.swift
//  Kotek
//
//  The AI overview (`SessionOverviewModel`) as the results screen's feedback:
//  the summary, the suggestion and the books behind it, all on show.
//
//  Replaces `SessionOverviewCard`. The card sat full-width under the graph,
//  which on a landscape phone put it below the fold; here it lives in the
//  right-hand column between the counts and the buttons.
//
//  R The suggestion and the books were behind "Show more". Three short
//  R pieces do not need hiding: on iPad the column had room to spare, and on
//  R a landscape phone the column scrolls under pinned Retry anyway. A sheet
//  R was the other option, and would have covered the graph the advice is
//  R about. The summary was Katibeh; the display face is for headings, and a
//  R paragraph of it read as a different voice from the rest of the screen.
//

import SwiftUI

struct ResultsFeedbackView: View {
    let model: SessionOverviewModel

    var body: some View {
        switch model.phase {
        case .hidden, .failed:
            // R A failed overview is dropped, not apologised for: the counts
            // R and the graph are the result, and this is commentary on them.
            EmptyView()
        case let .notice(text):
            section {
                Text(text)
                    .font(.sans(14))
                    .foregroundStyle(Theme.stone)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .thinking:
            section {
                Text("Going back over your session…")
                    .font(.sans(15))
                    .foregroundStyle(Theme.stone)
                    .phaseAnimator([0.45, 1.0]) { view, opacity in
                        view.opacity(opacity)
                    } animation: { _ in .easeInOut(duration: 0.9) }
            }
        case .writing, .done:
            section {
                Text(model.summary)
                    .font(.sans(17, weight: .semibold))
                    .foregroundStyle(Theme.charcoal)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeOut(duration: 0.15), value: model.summary)

                if !model.suggestion.isEmpty {
                    Label {
                        Text(model.suggestion)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.symbol(13, weight: .semibold))
                            .foregroundStyle(Theme.terracotta)
                    }
                    .font(.sans(15))
                    .foregroundStyle(Theme.charcoal.opacity(0.85))
                }

                if model.phase == .done {
                    citations
                    // Always visible: an AI's advice should never be
                    // mistaken for the teacher's own words.
                    Text("Written on this \(UIDevice.current.model) by Apple Intelligence.")
                        .font(.sans(11))
                        .foregroundStyle(Theme.stone.opacity(0.8))
                }
            }
        }
    }

    /// The books the overview was given pages from, each a way to go and find
    /// them.
    @ViewBuilder
    private var citations: some View {
        if !model.citations.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Drawing on")
                    .font(.sans(12, weight: .medium))
                    .foregroundStyle(Theme.stone)
                    .padding(.bottom, 2)
                ForEach(model.citations) { citation in
                    if let url = citation.book.url {
                        // R Opens in Safari, not in-app: it is the publisher's
                        // R page, and somebody about to buy a book wants the
                        // R real browser.
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "book.closed")
                                    .font(.symbol(12))
                                Text(citation.label)
                                Image(systemName: "arrow.up.right")
                                    .imageScale(.small)
                            }
                            .font(.sans(13, weight: .medium))
                            .foregroundStyle(Theme.gold)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .accessibilityHint("Opens where to get this book in Safari")
                    } else {
                        Text(citation.label)
                            .font(.sans(13, weight: .medium))
                            .foregroundStyle(Theme.stone)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private func section(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionLabel("Feedback", color: Theme.stone)
                Image(systemName: "sparkles")
                    .font(.sans(11))
                    .foregroundStyle(Theme.terracotta)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

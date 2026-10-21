//
//  ResultsFeedbackView.swift
//  Kotek
//
//  The AI overview (`SessionOverviewModel`) as the results screen's feedback:
//  the summary as one line, the suggestion and the books behind a tap.
//
//  Replaces `SessionOverviewCard`. The card sat full-width under the graph,
//  which on a landscape phone put it below the fold; here it lives in the
//  right-hand column between the counts and the buttons.
//

import SwiftUI

struct ResultsFeedbackView: View {
    let model: SessionOverviewModel

    @State private var expanded = false

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
                    .font(.serif(20))
                    .foregroundStyle(Theme.charcoal)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeOut(duration: 0.15), value: model.summary)

                if model.phase == .done {
                    // Always visible, not behind the tap: an AI's advice
                    // should never be mistaken for the teacher's own words.
                    Text("Written on this iPhone by Apple Intelligence.")
                        .font(.sans(11))
                        .foregroundStyle(Theme.stone.opacity(0.8))
                }

                if expanded {
                    VStack(alignment: .leading, spacing: 6) {
                        if !model.suggestion.isEmpty {
                            Text(model.suggestion)
                                .font(.sans(15, weight: .medium))
                                .foregroundStyle(Theme.terracotta)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        citations
                    }
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var hasMore: Bool {
        model.phase == .done && (!model.suggestion.isEmpty || !model.citations.isEmpty)
    }

    /// The books the overview was given pages from, each a way to go and find
    /// them.
    @ViewBuilder
    private var citations: some View {
        if !model.citations.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Drawing on:")
                    .font(.sans(11))
                    .foregroundStyle(Theme.stone.opacity(0.8))
                ForEach(model.citations) { citation in
                    if let url = citation.book.url {
                        // R Opens in Safari, not in-app: it is the publisher's
                        // R page, and somebody about to buy a book wants the
                        // R real browser.
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Text(citation.label)
                                Image(systemName: "arrow.up.right")
                                    .imageScale(.small)
                            }
                            .font(.sans(12, weight: .medium))
                            .foregroundStyle(Theme.gold)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .accessibilityHint("Opens where to get this book in Safari")
                    } else {
                        Text(citation.label)
                            .font(.sans(12, weight: .medium))
                            .foregroundStyle(Theme.stone)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private func section(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionLabel("Feedback", color: Theme.stone)
                Image(systemName: "sparkles")
                    .font(.sans(11))
                    .foregroundStyle(Theme.terracotta)
                Spacer()
                if hasMore {
                    Button(expanded ? "Show less" : "Show more") {
                        withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
                    }
                    .buttonStyle(.appPlain)
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.terracotta)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

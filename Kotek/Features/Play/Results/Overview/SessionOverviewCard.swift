//
//  SessionOverviewCard.swift
//  Kotek
//
//  The AI overview under the results, as it streams in.
//

import SwiftUI

struct SessionOverviewCard: View {
    let model: SessionOverviewModel

    var body: some View {
        switch model.phase {
        case .hidden, .failed:
            // R A failed overview is dropped, not apologised for: the score
            // R above it is the result, and this is commentary on it.
            EmptyView()
        case let .notice(text):
            card {
                Text(text)
                    .font(.sans(14))
                    .foregroundStyle(Theme.stone)
            }
        case .thinking:
            card {
                Text("Going back over your session…")
                    .font(.sans(15))
                    .foregroundStyle(Theme.stone)
                    .phaseAnimator([0.45, 1.0]) { view, opacity in
                        view.opacity(opacity)
                    } animation: { _ in .easeInOut(duration: 0.9) }
            }
        case .writing, .done:
            card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.summary)
                        .font(.sans(15))
                        .foregroundStyle(Theme.charcoal)
                    if !model.suggestion.isEmpty {
                        Text(model.suggestion)
                            .font(.sans(15, weight: .medium))
                            .foregroundStyle(Theme.terracotta)
                    }
                    if model.phase == .done {
                        credit
                            .padding(.top, 2)
                    }
                }
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeOut(duration: 0.15), value: model.summary)
            }
        }
    }

    /// Says what wrote it and from what. An AI's advice should never be
    /// mistaken for the teacher's own words, and the books it drew on get
    /// their pages cited and a way to go and find them.
    private var credit: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Written on this iPhone by Apple Intelligence\(model.citations.isEmpty ? "." : ", drawing on:")")
                .font(.sans(11))
                .foregroundStyle(Theme.stone.opacity(0.8))
            ForEach(model.citations) { citation in
                if let url = citation.book.url {
                    // R Opens in Safari, not in-app: it is the publisher's page,
                    // R and somebody about to buy a book wants the real browser.
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

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Overview", color: Theme.stone)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.deep.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.radius))
    }
}

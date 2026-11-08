//
//  PracticeHistoryView.swift
//  Kotek
//
//  Every session filed for the active gangsa, newest first. Read from the
//  server, not the phone: sessions are only ever uploaded, so this is also
//  where the ones played on another device show up.
//

import OSLog
import SwiftUI

struct PracticeHistoryView: View {
    @Environment(AppState.self) private var app

    private enum Load {
        case loading
        case loaded([PracticeHistoryRow])
        case failed
    }

    @State private var load = Load.loading

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                title: "History",
                onBack: { app.closeHistory() },
                trailingText: LocalizedStringKey(app.profile.name)
            )

            switch load {
            case .loading:
                ProgressView()
                    .tint(Theme.cream)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                message("Couldn't load your history. Check your connection and try again.")
            case let .loaded(rows) where rows.isEmpty:
                message("No sessions yet on \(app.profile.name). Finish one and it shows up here.")
            case let .loaded(rows):
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(rows) { row in
                            HistoryRowView(row: row, kotekanName: kotekanName(row.kotekanID))
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)
                }
            }
        }
        .task(id: app.profile.id) { await refresh() }
    }

    private func refresh() async {
        load = .loading
        do {
            load = try await .loaded(app.sessionRepo.history(instrumentID: app.profile.id))
        } catch {
            app.log.error("history fetch failed: \(error.localizedDescription)")
            load = .failed
        }
    }

    private func kotekanName(_ id: String?) -> String {
        guard let id else { return String(localized: "Unknown kotekan") }
        return app.kotekans.first { $0.id == id }?.name ?? String(localized: "Unknown kotekan")
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.sans(16))
            .foregroundStyle(Theme.cream.opacity(0.72))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HistoryRowView: View {
    let row: PracticeHistoryRow
    let kotekanName: String

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kotekanName)
                    .font(.serif(22))
                    .foregroundStyle(Theme.heading)
                Text(subtitle)
                    .font(.sans(13))
                    .foregroundStyle(Theme.cream.opacity(0.62))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            stat(row.accuracy.map { Theme.percentLabel($0) } ?? "—", "accuracy")
            stat(row.landedNotes.formatted(), "notes")
            stat(row.bestStreak.formatted(), "streak")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Theme.deep, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(Theme.cream.opacity(0.12), lineWidth: 1)
        )
    }

    /// "Polos · 75% tempo · 2 hours ago"
    private var subtitle: String {
        var parts = [KotekanHalf(rawValue: row.half)?.title ?? row.half.capitalized]
        if row.tempoScale != 1 { parts.append(String(localized: "\(Int((row.tempoScale * 100).rounded()))% tempo")) }
        if let date = InstrumentProfile.date(from: row.createdAt) {
            parts.append(date.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.sans(20, weight: .semibold))
                .foregroundStyle(Theme.cream)
                .monospacedDigit()
            Text(label)
                .font(.sans(12, weight: .medium))
                .foregroundStyle(Theme.cream.opacity(0.55))
        }
        .frame(width: 84)
    }
}

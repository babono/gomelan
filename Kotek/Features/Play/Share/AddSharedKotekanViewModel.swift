//
//  AddSharedKotekanViewModel.swift
//  Kotek
//
//  The add screen's state: the figure behind the link, the gangsa chosen for
//  it, and the copy being made. Adding makes the player a copy of their own
//  (`AppState.addSharedKotekan`); nothing here talks to Supabase but through
//  the repository.
//

import FactoryKit
import Foundation
import Observation

@Observable
final class AddSharedKotekanViewModel {
    private(set) var phase = AddSharedKotekanPhase.loading
    private(set) var isAdding = false
    private(set) var addFailed = false
    /// The gangsa card in the middle of the rail.
    var chosenGangsa: String?

    let id: String
    private let app: AppState
    private let repository: KotekanRepository
    @ObservationIgnored private var addTask: Task<Void, Never>?

    init(id: String, app: AppState, repository: KotekanRepository = Container.shared.kotekanRepository()) {
        self.id = id
        self.app = app
        self.repository = repository
        // The gangsa in play, else the first: the one most likely meant.
        chosenGangsa = app.savedProfiles.contains { $0.id == app.profile.id }
            ? app.profile.id
            : app.savedProfiles.first?.id
    }

    var gangsa: [InstrumentProfile] {
        app.savedProfiles
    }

    var kotekan: Kotekan? {
        if case let .ready(k) = phase { k } else { nil }
    }

    var chosen: InstrumentProfile? {
        gangsa.first { $0.id == chosenGangsa }
    }

    var canAdd: Bool {
        kotekan != nil && chosen != nil && !isAdding
    }

    /// Called from `.task(id:)`, so leaving the screen cancels it.
    func load() async {
        phase = .loading
        do {
            let remote = try await repository.shared(id: id)
            phase = remote.map { .ready(Kotekan(remote: $0)) } ?? .notFound
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
        }
    }

    func add() {
        guard canAdd, let instrument = chosen else { return }
        addTask?.cancel()
        isAdding = true
        addFailed = false
        addTask = Task { [weak self, id, app] in
            do {
                // Closes the screen on success: it clears `pendingShare`.
                try await app.addSharedKotekan(id: id, to: instrument)
            } catch is CancellationError {
            } catch {
                self?.addFailed = true
            }
            self?.isAdding = false
        }
    }

    /// A gangsa first, then the link again — Kipli says so.
    func addGangsa() {
        close()
        app.addNewInstrument()
    }

    func close() {
        addTask?.cancel()
        app.pendingShare = nil
    }

    // MARK: - Kipli

    var kipliMood: KipliGuide.Mood {
        switch phase {
        case .notFound, .failed: .sad
        case .loading, .ready: addFailed ? .sad : .happy
        }
    }

    var kipliMessage: LocalizedStringResource {
        switch phase {
        case .loading:
            return "Hang on, I'm fetching the kotekan…"
        case .notFound:
            return "This link doesn't lead to a kotekan any more. Its owner may have deleted it."
        case .failed:
            return "Couldn't open it. Check your connection and try again."
        case let .ready(k):
            if gangsa.isEmpty { return "Set up your gangsa first, then open the link to \(k.name) again." }
            if addFailed { return "Couldn't add it. Check your connection and try again." }
            if isAdding, let name = chosen?.name { return "Putting it on \(name)…" }
            return "Choose the gangsa it goes on. You get your own copy, yours to change."
        }
    }
}

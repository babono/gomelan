//
//  AddSharedKotekanViewModel.swift
//  Kotek
//
//  The add screen's state: the figure behind the link, the gangsa chosen for
//  it, and the copy being made. Adding makes the player a copy of their own
//  (`AppState.addSharedKotekan`); nothing here talks to Supabase but through
//  the repository.
//
//  The same screen copies one of the player's own figures onto another of
//  their gangsa (`Source.copy`, from the picker's card menu,
//  `AppState.copyKotekan`): the figure is already here, and the gangsa are
//  the others.
//

import FactoryKit
import Foundation
import Observation

@Observable
final class AddSharedKotekanViewModel {
    enum Source {
        /// A link's figure, by id: fetched, then copied past row-level security.
        case shared(String)
        /// The player's own figure, to another of their gangsa.
        case copy(Kotekan)
    }

    let source: Source
    private(set) var phase = AddSharedKotekanPhase.loading
    private(set) var isAdding = false
    private(set) var addFailed = false
    /// The gangsa card in the middle of the rail.
    var chosenGangsa: String?

    /// The link's figure id, or the copied one's: the screen's identity.
    let id: String
    private let app: AppState
    private let repository: KotekanRepository
    @ObservationIgnored private var addTask: Task<Void, Never>?

    init(source: Source, app: AppState, repository: KotekanRepository = Container.shared.kotekanRepository()) {
        self.source = source
        self.app = app
        self.repository = repository
        switch source {
        case let .shared(id):
            self.id = id
            // The gangsa in play, else the first: the one most likely meant.
            chosenGangsa = app.savedProfiles.contains { $0.id == app.profile.id }
                ? app.profile.id
                : app.savedProfiles.first?.id
        case let .copy(k):
            id = k.id
            phase = .ready(k)
            chosenGangsa = app.savedProfiles.first { $0.id != app.profile.id }?.id
        }
    }

    var isCopy: Bool {
        if case .copy = source { true } else { false }
    }

    var gangsa: [InstrumentProfile] {
        #if DEBUG
            if app.sharePreview == .noGangsa { return [] }
        #endif
        // A copy goes to the others. The one in play, not the figure's own: a
        // figure filed on no gangsa is on every one, and would leave none.
        if isCopy { return app.savedProfiles.filter { $0.id != app.profile.id } }
        return app.savedProfiles
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
        if isCopy { return }
        #if DEBUG
            if let preview = app.sharePreview {
                phase = preview == .brokenLink ? .notFound : .ready(Kotekan.bundled[0])
                return
            }
        #endif
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
        #if DEBUG
            // A preview's figure is bundled, not shared: nothing to copy.
            if app.sharePreview != nil { return close() }
        #endif
        addTask?.cancel()
        isAdding = true
        addFailed = false
        addTask = Task { [weak self, id, app, source] in
            do {
                // Closes the screen on success: it clears `pendingShare`, or
                // `copyingKotekan`.
                if case let .copy(k) = source {
                    try await app.copyKotekan(k, to: instrument)
                } else {
                    try await app.addSharedKotekan(id: id, to: instrument)
                }
            } catch is CancellationError {
            } catch {
                self?.addFailed = true
            }
            self?.isAdding = false
        }
    }

    /// A gangsa first, then the link again — Kipli says so.
    func addGangsa() {
        #if DEBUG
            if app.sharePreview != nil { return close() }
        #endif
        close()
        app.addNewInstrument()
    }

    func close() {
        addTask?.cancel()
        if isCopy {
            app.copyingKotekan = nil
            return
        }
        app.pendingShare = nil
        #if DEBUG
            app.sharePreview = nil
        #endif
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
        case let .ready(k) where isCopy:
            if addFailed { return "Couldn't copy it. Check your connection and try again." }
            if isAdding, let name = chosen?.name { return "Copying it to \(name)…" }
            return "Choose the gangsa to copy \(k.name) to. The copy is its own, so changing one leaves the other."
        case let .ready(k):
            if gangsa.isEmpty { return "Set up your gangsa first, then open the link to \(k.name) again." }
            if addFailed { return "Couldn't add it. Check your connection and try again." }
            if isAdding, let name = chosen?.name { return "Putting it on \(name)…" }
            return "Choose the gangsa it goes on. You get your own copy, yours to change."
        }
    }
}

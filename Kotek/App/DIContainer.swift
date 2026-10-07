//
//  DIContainer.swift
//  Kotek
//
//  Created by Dimas Nugraha on 04/10/26.
//

import FactoryKit

extension Container {
    /// One client for the app's lifetime: it owns the anonymous session, and a
    /// second instance would race the first to refresh it.
    @MainActor
    var router: Factory<AppState> {
        self { AppState() }.singleton
    }

    // MARK: Repositories init

    nonisolated var supabaseRepository: Factory<SupabaseRepository> {
        self { SupabaseRepository() }.singleton
    }

    nonisolated var instrumentRemoteRepository: Factory<InstrumentRemoteRepository> {
        self { InstrumentRemoteRepository(remote: self.supabaseRepository()) }.singleton
    }

    nonisolated var kotekanRepository: Factory<KotekanRepository> {
        self { KotekanRepository(remote: self.supabaseRepository()) }.singleton
    }

    nonisolated var practiceSessionRepository: Factory<PracticeSessionRepository> {
        self {
            PracticeSessionRepository(
                remote: self.supabaseRepository(),
                instrumentRepository: self.instrumentRemoteRepository()
            )
        }.singleton
    }

    // MARK: Services / Controller Init

    nonisolated var cameraService: Factory<CameraController> {
        self { CameraController() }.singleton
    }

    nonisolated var audioService: Factory<AudioEngineController> {
        self { MainActor.assumeIsolated { AudioEngineController() } }.singleton
    }

    nonisolated var cueService: Factory<CuePlayer> {
        self { MainActor.assumeIsolated { CuePlayer() } }.singleton
    }

    nonisolated var preloaderService: Factory<Preloader> {
        self { MainActor.assumeIsolated { Preloader() } }.singleton
    }
}

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
    nonisolated var remote: Factory<RemoteStore> {
        self { RemoteStore() }.singleton
    }

    // MARK: Services / Controller Init  
    nonisolated var cameraService: Factory<CameraController> {
        self { CameraController() }.singleton
    }
}

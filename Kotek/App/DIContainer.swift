//
//  DIContainer.swift
//  Kotek
//
//  Created by Dimas Nugraha on 04/10/26.
//

import FactoryKit

extension Container {
    @MainActor
    var router: Factory<AppState> {
        self { AppState() }.singleton
    }

    // MARK: Services / Controller Init
    nonisolated var cameraService: Factory<CameraController> {
        self { CameraController() }.singleton
    }
}

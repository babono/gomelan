//
//  PermissionsView.swift
//  Kotek
//
//  Camera + microphone permission gate (PRD §8, §13.4). Both are required: the
//  camera to see the gangsa, the mic to hear which key was struck.
//

import FactoryKit
import SwiftUI

struct PermissionsView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController

    init(camera: CameraController = Container.shared.cameraService()) {
        self.camera = camera
    }

    var body: some View {
        VStack(spacing: 20) {
            ProgressView().tint(Theme.copper)
            SectionLabel("Requesting camera and microphone", color: Theme.inkStone)
        }
        .task {
            let cameraOK = await camera.requestAccess()
            let micOK = await AudioSessionManager.requestRecordPermission()
            app.permissionsResolved(granted: cameraOK && micOK)
        }
    }
}

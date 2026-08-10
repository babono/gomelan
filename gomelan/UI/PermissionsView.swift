//
//  PermissionsView.swift
//  gomelan
//
//  Camera + microphone permission gate (PRD §8, §13.4). Both are required: the
//  camera to see the gangsa, the mic to hear which key was struck.
//

import SwiftUI

struct PermissionsView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(Theme.accent)
            Text("Requesting camera and microphone access…")
                .foregroundStyle(.white.opacity(0.8))
        }
        .task {
            let cameraOK = await camera.requestAccess()
            let micOK = await AudioSessionManager.requestRecordPermission()
            app.permissionsResolved(granted: cameraOK && micOK)
        }
    }
}

struct PermissionsBlockedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.metering.none")
                .font(.system(size: 60))
                .foregroundStyle(Theme.miss)
            Text("Camera and microphone access are required")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text("Gomelan needs to see your gangsa and hear which key you play. Enable both in Settings to continue.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            SecondaryButton(title: "Open Settings", systemImage: "gear") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
        .padding(40)
    }
}

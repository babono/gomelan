//
//  PermissionsView.swift
//  Kotek
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

struct PermissionsBlockedView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.metering.none")
                .font(.system(size: 54))
                .foregroundStyle(Theme.terracotta)
            Text("Camera and microphone access are required")
                .font(.serif(30))
                .foregroundStyle(Theme.charcoal)
                .multilineTextAlignment(.center)
            Text("Gomelan needs to see your gangsa and hear which key you play. Enable both in Settings to continue.")
                .font(.sans(15))
                .foregroundStyle(Theme.stone)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
                .lineSpacing(4)
            PillButton(title: "Open Settings", systemImage: "gear", style: .outlined, uppercase: false) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .padding(.top, 8)
        }
        .padding(40)
    }
}

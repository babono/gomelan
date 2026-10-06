//
//  PermissionsBlockedView.swift
//  Kotek
//
//  Camera and microphone permissions blocked resolution screen.
//

import SwiftUI

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
            Text("Kotek needs to see your gangsa and hear which key you play. Enable both in Settings to continue.")
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

//
//  CameraSettingsSectionView.swift
//  Kotek
//
//  Settings card for camera mount focus and exposure locking.
//

import SwiftUI

struct CameraSettingsSectionView: View {
    @Bindable var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Fixed mount (stand or arm)", isOn: $app.fixedMount)
                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
            Text(
                app.fixedMount
                    ? "Focus and exposure lock once the scene is set. Steadier image, and the keys stay where you aligned them — the right choice on a stand."
                    : "Focus and exposure follow the scene, for a handheld phone. On a stand this hunts every time a hand crosses the keys."
            )
            .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 360)
        }
    }
}

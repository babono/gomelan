//
//  CameraSettingsSectionView.swift
//  Kotek
//
//  Camera mount focus and exposure locking, inside the Deprecated card.
//

import SwiftUI

struct CameraSettingsSectionView: View {
    @Bindable var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Phone on a stand", isOn: $app.fixedMount)
                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
            Text(
                app.fixedMount
                    ? "Focus and exposure stay locked."
                    : "Focus and exposure adjust as you move. For holding the phone."
            )
            .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 360)
        }
    }
}

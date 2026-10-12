//
//  DeprecatedSectionView.swift
//  Kotek
//
//  Settings card for the camera-first play mode the waterfall replaced.
//

import SwiftUI

struct DeprecatedSectionView: View {
    @Bindable var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Top view", isOn: $app.topView)
                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
            Text(
                app.topView
                    ? "A kotekan plays on the live camera, looking down on the real bilah. Realign the keys first — a new gangsa is no longer aligned during setup."
                    : "A kotekan plays on the waterfall: notes fall onto a drawn gangsa, no camera needed."
            )
            .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 360)
        }
    }
}

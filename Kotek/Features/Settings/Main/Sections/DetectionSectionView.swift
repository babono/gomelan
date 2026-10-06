//
//  DetectionSectionView.swift
//  Kotek
//
//  Settings card for selecting detection mode (camera, heardOnly, corroborated).
//

import SwiftUI

struct DetectionSectionView: View {
    @Bindable var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(
                "Detection",
                selection: Binding(
                    get: { app.detectionMode },
                    set: { app.detectionMode = $0 }
                )
            ) {
                ForEach(AppState.DetectionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .kajarOnChange(of: app.detectionMode)
            .frame(maxWidth: 400)

            Text(app.detectionMode.detail)
                .font(.sans(13))
                .foregroundStyle(Theme.cream.opacity(0.75))
                .frame(maxWidth: 400)

            if app.detectionMode == .heardOnly, app.yourVoiceAudible {
                Text(
                    "Your half is playing through the speaker on the same keys you strike, which raises the bar an attack has to clear. Mute it under Audio cues if strikes start going missing."
                )
                .font(.sans(13))
                .foregroundStyle(Theme.miss)
                .frame(maxWidth: 400)
            }
        }
    }
}

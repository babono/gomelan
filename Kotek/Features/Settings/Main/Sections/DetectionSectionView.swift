//
//  DetectionSectionView.swift
//  Kotek
//
//  Detection mode (camera, heardOnly, corroborated), inside the Deprecated card.
//

import SwiftUI

struct DetectionSectionView: View {
    @Bindable var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(
                "Hit detection",
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

            if app.profile.controller != nil {
                Text(
                    app.controllerConnected
                        ? "Keys with sensors use the controller. This is for the rest."
                        : "Used for all keys until the controller connects."
                )
                .font(.sans(13))
                .foregroundStyle(Theme.cream.opacity(0.75))
                .frame(maxWidth: 400)
            }

            if app.detectionMode == .heardOnly, app.yourVoiceAudible {
                Text(
                    "The guide sound can hide your hits. Turn Guide off if hits are missed."
                )
                .font(.sans(13))
                .foregroundStyle(Theme.miss)
                .frame(maxWidth: 400)
            }
        }
    }
}

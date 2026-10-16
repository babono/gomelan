//
//  DeprecatedSectionView.swift
//  Kotek
//
//  Settings card for the camera-first play mode the waterfall replaced, with
//  the two settings only it reads: how the camera is mounted, and what counts
//  as a stroke. The waterfall reads neither, so they were two whole cards for
//  a mode most players never turn on. The Debug test screens read them too.
//  Re-align keys and Calibrate voice live here for the same reason: the
//  camera mode is the only thing that uses the key rects and learned voice.
//

import SwiftUI

struct DeprecatedSectionView: View {
    @Bindable var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            topView
            FlowLayout(spacing: 10) {
                SecondaryButton(title: "Re-align keys", systemImage: "viewfinder") {
                    app.realign()
                }
                SecondaryButton(title: "Calibrate voice", systemImage: "waveform") {
                    app.openCalibration()
                }
            }
            CameraSettingsSectionView(app: app)
            VStack(alignment: .leading, spacing: 10) {
                Text("Detection")
                    .font(.sans(15)).foregroundStyle(Theme.cream)
                DetectionSectionView(app: app)
            }
        }
    }

    private var topView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Top view", isOn: $app.topView)
                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
            Text(
                app.topView
                    ? "Play on the live camera. Realign the keys first."
                    : "Play on the waterfall. No camera needed."
            )
            .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 360)
        }
    }
}

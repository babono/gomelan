//
//  DebugSectionView.swift
//  Kotek
//
//  Settings card providing shortcuts to developer and diagnostic test screens.
//

import SwiftUI

struct DebugSectionView: View {
    let app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(KotekFonts.summary)
                .font(.sans(11).monospacedDigit())
                .foregroundStyle(KotekFonts.displayRegular == nil ? Theme.miss : Theme.cream.opacity(0.75))

            FlowLayout(spacing: 10) {
                AppButton(title: "Test Mallet", systemImage: "scope", size: .compact) {
                    app.openMalletTest()
                }
                AppButton(title: "Test Detection", systemImage: "dot.radiowaves.left.and.right", size: .compact) {
                    app.openDetectionTest()
                }
                AppButton(title: "Test Audio", systemImage: "waveform.circle", size: .compact) {
                    app.openAudioTest()
                }
                AppButton(title: "Capture Training Data", systemImage: "camera.viewfinder", size: .compact) {
                    app.openCaptureTraining()
                }
                AppButton(title: "Test Sensors", systemImage: "sensor.tag.radiowaves.forward", size: .compact) {
                    app.openSensorTest()
                }
            }
        }
    }
}

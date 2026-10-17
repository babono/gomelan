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
                AppButton("Test Mallet", systemImage: "scope") {
                    app.openMalletTest()
                }
                AppButton("Test Detection", systemImage: "dot.radiowaves.left.and.right") {
                    app.openDetectionTest()
                }
                AppButton("Test Audio", systemImage: "waveform.circle") {
                    app.openAudioTest()
                }
                AppButton("Capture Training Data", systemImage: "camera.viewfinder") {
                    app.openCaptureTraining()
                }
                AppButton("Test Sensors", systemImage: "sensor.tag.radiowaves.forward") {
                    app.openSensorTest()
                }
            }
        }
    }
}

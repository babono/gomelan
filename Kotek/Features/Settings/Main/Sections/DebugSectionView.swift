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
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(KotekFonts.displayRegular == nil ? Theme.miss : Theme.cream.opacity(0.75))

            FlowLayout(spacing: 10) {
                SecondaryButton(title: "Test Mallet", systemImage: "scope") {
                    app.openMalletTest()
                }
                SecondaryButton(title: "Test Detection", systemImage: "dot.radiowaves.left.and.right") {
                    app.openDetectionTest()
                }
                SecondaryButton(title: "Test Audio", systemImage: "waveform.circle") {
                    app.openAudioTest()
                }
                SecondaryButton(title: "Capture Training Data", systemImage: "camera.viewfinder") {
                    app.openCaptureTraining()
                }
            }
        }
    }
}

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
            FlowLayout(spacing: 10) {
                AppButton(title: "Test Sensors", systemImage: "sensor.tag.radiowaves.forward", size: .compact) {
                    app.openSensorTest()
                }
                #if DEBUG
                    AppButton(title: "View Mock Results", systemImage: "chart.line.uptrend.xyaxis", size: .compact) {
                        app.openMockResults()
                    }
                    // The add-shared-kotekan screen in each state, no link needed.
                    AppButton(title: "Share: regular", systemImage: "link", size: .compact) {
                        app.openSharePreview(.regular)
                    }
                    AppButton(title: "Share: no gangsa", systemImage: "link", size: .compact) {
                        app.openSharePreview(.noGangsa)
                    }
                    AppButton(title: "Share: broken link", systemImage: "exclamationmark.triangle", size: .compact) {
                        app.openSharePreview(.brokenLink)
                    }
                    AppButton(title: "Share: sign in with Apple", systemImage: "apple.logo", size: .compact) {
                        app.openSharePreview(.signIn)
                    }
                #endif
            }
        }
    }
}

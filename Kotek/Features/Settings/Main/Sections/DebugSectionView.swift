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
                #endif
            }
        }
    }
}

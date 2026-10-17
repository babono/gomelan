//
//  PauseOverlay.swift
//  Kotek
//
//  Stopped, but not over — and the ONLY way out of a session.
//

import SwiftUI

struct PauseOverlay: View {
    let onResume: () -> Void
    let onShowAround: () -> Void
    let onEndPractice: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 22) {
                Text("Paused").font(.serif(44)).foregroundStyle(Theme.cream)
                HStack(spacing: 16) {
                    AppButton("Resume", prominence: .primary, size: .large) {
                        onResume()
                    }
                    AppButton(
                        "Show me around"
                    ) {
                        onShowAround()
                    }
                    AppButton(
                        "End practice"
                    ) {
                        onEndPractice()
                    }
                }
            }
        }
    }
}

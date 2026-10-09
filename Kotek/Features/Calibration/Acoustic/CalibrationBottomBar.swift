//
//  CalibrationBottomBar.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// Bottom strip showing microphone feedback, strike progress, and capture controls.
struct CalibrationBottomBar: View {
    let learned: Bool
    let lastAccepted: Bool?
    let micLevel: Float
    let micLevelTime: Double
    let strikeCount: Int
    let strikesNeeded: Int
    let confidence: Double
    let committing: Bool
    let onReset: () -> Void
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    SectionLabel(
                        learned
                            ? "Kotek knows this gangsa's voice"
                            : "Strike any key — soft, then hard",
                        color: Theme.copper
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                    if let lastAccepted {
                        Label(
                            lastAccepted ? "heard a strike" : "ignored — didn't match the others",
                            systemImage: lastAccepted ? "checkmark.circle" : "xmark.circle"
                        )
                        .font(.sans(12, weight: .medium))
                        .foregroundStyle(lastAccepted ? Theme.cream : Theme.inkStone)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                    }
                }

                MicSpectrumView(micLevel: micLevel, micLevelTime: micLevelTime, height: 26)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StrikeMeterView(
                strikeCount: strikeCount,
                strikesNeeded: strikesNeeded,
                confidence: confidence
            )

            PillButton(title: "Reset", style: .outlined, tint: Theme.inkStone, compact: true) {
                onReset()
            }

            PillButton(
                title: learned ? "Continue" : "Listening…",
                trailingSystemImage: learned ? "arrow.right" : nil,
                style: learned ? .filled : .outlined,
                tint: Theme.copper,
                compact: true
            ) {
                if learned { onCommit() }
            }
            .disabled(!learned || committing)
            .opacity(learned ? 1 : 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: [.bottom, .horizontal])
        )
    }
}

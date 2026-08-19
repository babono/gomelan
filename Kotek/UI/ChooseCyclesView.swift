//
//  ChooseCyclesView.swift
//  Kotek
//
//  Dedicated screen for choosing repetition / cycle count (e.g. 4×, 8×, 12×)
//  after selecting song and half. Styled consistently on warm cream paper.
//

import SwiftUI

struct ChooseCyclesView: View {
    @Environment(AppState.self) private var app

    @State private var cycles: Int = 8
    private let range = 1...32

    var body: some View {
        if let k = app.selectedKotekan {
            VStack(spacing: 0) {
                TopBar(title: "How many cycles?",
                       backTitle: "Back",
                       onBack: { app.backToHalf() },
                       trailingText: "\(k.name) · \(app.chosenHalf.title)",
                       settingsAction: { app.openSettings() })

                HStack(alignment: .center, spacing: 0) {
                    // Question + info
                    VStack(alignment: .leading, spacing: 18) {
                        SectionLabel("Repetition")

                        Text("How many times around?")
                            .font(.serif(40))
                            .foregroundStyle(Theme.charcoal)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Each cycle loops through one complete gong pattern. More cycles help build muscle memory and steady rhythm.")
                            .font(.sans(15))
                            .foregroundStyle(Theme.stone)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 32)

                    Rectangle().fill(Theme.charcoal.opacity(0.15)).frame(width: 1, height: 220)

                    // Stepper + CTA
                    VStack(spacing: 26) {
                        CountStepper(value: $cycles, range: range, numberSize: 76)

                        Text("\(cycles)× cycles · ~\(estimatedDuration(k, cycles: cycles))")
                            .font(.sans(14, weight: .medium))
                            .foregroundStyle(Theme.terracotta)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Theme.terracotta.opacity(0.12), in: Capsule())

                        // The session opens with the demo: hear the figure first,
                        // then take the mallets.
                        PillButton(title: "Watch & listen", style: .filled, tint: Theme.terracotta) {
                            app.startSession(cycles: cycles)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.leading, 32)
                }
                .padding(.horizontal, 40)
                .frame(maxHeight: .infinity)
            }
            .onAppear { cycles = app.chosenCycles }
        } else {
            Color.clear.onAppear { app.backToKotekan() }
        }
    }

    private func estimatedDuration(_ k: Kotekan, cycles: Int) -> String {
        let totalSeconds = Int(Double(cycles * k.slotsPerCycle * k.strokeMs) / 1000.0)
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        } else {
            let m = totalSeconds / 60
            let s = totalSeconds % 60
            return s > 0 ? "\(m)m \(s)s" : "\(m)m"
        }
    }
}

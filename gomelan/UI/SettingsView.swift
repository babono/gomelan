//
//  SettingsView.swift
//  gomelan
//
//  Settings (PRD §8): recalibrate, tempo, audio cues, detection, and the dev
//  test screens.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            TopBar(title: "Settings",
                   backTitle: "Done",
                   onBack: { app.closeSettings() })

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    section("Instrument") {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.profile.name)
                                    .font(.serif(22)).foregroundStyle(Theme.charcoal)
                                Text("\(app.profile.keyCount) keys · \(app.profile.calibratedKeyCount) tuned")
                                    .font(.sans(14)).foregroundStyle(Theme.stone)
                            }

                            FlowLayout(spacing: 10) {
                                SecondaryButton(title: "Switch Instrument", systemImage: "arrow.triangle.2.circlepath") { app.openChooseInstrument() }
                                SecondaryButton(title: "Record voice baseline", systemImage: "waveform") { app.openCalibration() }
                                SecondaryButton(title: "Re-align keys", systemImage: "viewfinder") { app.realign() }
                            }
                        }
                    }

                    section("Debug") {
                        FlowLayout(spacing: 10) {
                            SecondaryButton(title: "Test Mallet", systemImage: "scope") { app.openMalletTest() }
                            SecondaryButton(title: "Test Detection", systemImage: "dot.radiowaves.left.and.right") { app.openDetectionTest() }
                            SecondaryButton(title: "Test Audio", systemImage: "waveform.circle") { app.openAudioTest() }
                        }
                    }

                    section("Practice tempo") {
                        Picker("Tempo", selection: $app.tempoScale) {
                            Text("50%").tag(0.5)
                            Text("75%").tag(0.75)
                            Text("100%").tag(1.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)
                    }

                    section("Audio cues") {
                        Toggle("Metronome click", isOn: $app.metronomeEnabled)
                            .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.charcoal)
                        Toggle("Reference tone (one beat ahead)", isOn: $app.referenceToneEnabled)
                            .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.charcoal)
                    }

                    section("Detection") {
                        Toggle("Require strike sound", isOn: $app.requireStrikeSound)
                            .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.charcoal)
                        Text(app.requireStrikeSound
                             ? "A hit only counts with a real gangsa strike sound — blocks hovering, but needs a learned baseline (Test Audio)."
                             : "Vision alone counts the hit. More forgiving; a hovered mallet can register.")
                            .font(.sans(13)).foregroundStyle(Theme.stone).frame(maxWidth: 360)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 28)
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title)
            content()
        }
    }
}

/// Custom wrapping flow layout for inline-block wrapping of pill buttons.
struct FlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                                  proposal: ProposedViewSize.unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxW = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var points: [CGPoint] = []
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize.unspecified)
            if currentX + size.width > maxW, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: totalWidth, height: totalHeight), points)
    }
}

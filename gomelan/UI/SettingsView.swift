//
//  SettingsView.swift
//  gomelan
//
//  Settings (PRD §8): recalibrate, tempo, audio cues.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        ScrollView {
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                Text("Settings").font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                Spacer()
                SecondaryButton(title: "Done", systemImage: "checkmark") { app.closeSettings() }
            }

            section("Instrument") {
                HStack {
                    VStack(alignment: .leading) {
                        Text(app.profile.name).foregroundStyle(.white)
                        Text("\(app.profile.keyCount) keys").font(.subheadline).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    SecondaryButton(title: "Record key pitches", systemImage: "waveform") { app.openCalibration() }
                    SecondaryButton(title: "Re-align keys", systemImage: "viewfinder") { app.realign() }
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
                    .tint(Theme.accent).frame(maxWidth: 360).foregroundStyle(.white)
                Toggle("Reference tone (one beat ahead)", isOn: $app.referenceToneEnabled)
                    .tint(Theme.accent).frame(maxWidth: 360).foregroundStyle(.white)
            }

            section("Detection") {
                Toggle("Require strike sound", isOn: $app.requireStrikeSound)
                    .tint(Theme.accent).frame(maxWidth: 360).foregroundStyle(.white)
                Text(app.requireStrikeSound
                     ? "A hit only counts with a real gangsa strike sound — blocks hovering, but needs a learned baseline (Test Audio)."
                     : "Vision alone counts the hit. More forgiving; a hovered mallet can register.")
                    .font(.caption).foregroundStyle(.white.opacity(0.5)).frame(maxWidth: 360)
            }

        }
        .padding(40)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accent.opacity(0.8))
            content()
        }
    }
}

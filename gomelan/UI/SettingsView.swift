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

            Spacer()
        }
        .padding(40)
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

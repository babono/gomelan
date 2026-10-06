//
//  AudioSectionView.swift
//  Kotek
//
//  Settings card for metronome, reference tone, and voice playback options.
//

import SwiftUI

struct AudioSectionView: View {
    @Bindable var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Metronome click", isOn: $app.metronomeEnabled)
                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
            Toggle("Reference tone (one beat ahead)", isOn: $app.referenceToneEnabled)
                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
            Toggle("Play my half as a guide", isOn: $app.yourVoiceAudible)
                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
            Text(
                app.yourVoiceAudible
                    ? "The app sounds the part you are learning, in time with the bilah, so you can copy it. Turn it off once the figure is in your hands — it is played back on the same keys you strike, so it also makes you harder to hear."
                    : "The bilah light up but stay silent. The only strokes in the room are yours."
            )
            .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 360)

            Toggle("Partner plays the other half", isOn: $app.partnerAudible)
                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
            Text(
                app.partnerAudible
                    ? "The app takes the other half, so the kotekan interlocks even when you practise alone. The gong layer is always there."
                    : "You play against the gong alone. Turn this on once the figure is steady — that is when it becomes a kotekan."
            )
            .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 360)
        }
    }
}

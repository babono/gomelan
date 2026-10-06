//
//  JudgingSectionView.swift
//  Kotek
//
//  Settings card for leniency, wrong bar penalty, and on-screen stroke calls.
//

import SwiftUI

struct JudgingSectionView: View {
    @Bindable var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Timing")
                    .font(.sans(15)).foregroundStyle(Theme.cream)
                Spacer()
                Text(
                    app.judgementLeniency <= 1.05
                        ? "As notated"
                        : (app.judgementLeniency >= 1.25 ? "Very forgiving" : "Forgiving")
                )
                .font(.sans(15)).foregroundStyle(Theme.cream.opacity(0.75))
            }
            .frame(maxWidth: 360)

            Slider(value: $app.judgementLeniency, in: 1.0...1.3, step: 0.05)
                .tint(Theme.terracotta).frame(maxWidth: 360)

            Text(
                app.judgementLeniency <= 1.05
                    ? "A stroke has to land where the figure puts it. The honest setting, and the hardest."
                    : "The same stroke earns a better grade, so a visitor who finds the right bilah is told so. It does not change whether a stroke registers — only what it scores."
            )
            .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 360)

            Toggle("Score wrong bars", isOn: $app.scoresWrongBar)
                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
            Text(
                app.scoresWrongBar
                    ? "A stroke on the wrong bilah takes the note that was due and scores it wrong. Right when the microphone is listening — a sound means a real stroke. On camera alone, a mallet travelling across a bar can take a note you were about to play."
                    : "A stroke on a bilah nothing is due on is ignored, and the note stays open for the right one. A bar genuinely played wrong becomes a miss instead."
            )
            .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 360)

            Toggle("Call each stroke", isOn: $app.callsStrokes)
                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
            Text(
                app.callsStrokes
                    ? "Each stroke says what it was — Perfect, Late, Miss — on the bilah you struck, and is gone within a second. A missed note leaves no other mark, so without this it simply disappears."
                    : "The bilah stay wordless. You will see a stroke land and nothing at all when one does not."
            )
            .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 360)
        }
    }
}

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

            Slider(value: $app.judgementLeniency, in: 1.0 ... 1.3, step: 0.05)
                .tint(Theme.terracotta).frame(maxWidth: 360)

            Text(
                app.judgementLeniency <= 1.05
                    ? "Strokes must land where the pattern puts them."
                    : "Near misses grade better. Only the score changes, not what registers."
            )
            .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 360)

            Toggle("Score wrong bars", isOn: $app.scoresWrongBar)
                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
            Text(
                app.scoresWrongBar
                    ? "A stroke on the wrong bilah counts against the note that was due."
                    : "Strokes on the wrong bilah are ignored; the note waits for the right one."
            )
            .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 360)

            Toggle("Call each stroke", isOn: $app.callsStrokes)
                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
            Text(
                app.callsStrokes
                    ? "Perfect, Late or Miss flashes on the bilah you struck."
                    : "No words on the bilah, and a missed note leaves no mark."
            )
            .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 360)
        }
    }
}

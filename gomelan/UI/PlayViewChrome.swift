//
//  PlayViewChrome.swift
//  gomelan
//
//  Created by Rhea Aulia on 11/08/26.
//
//  Small chrome shared by the two stage screens: the demo (WatchView) and the
//  run (PlayView). The score itself is NotesRiver.
//

import SwiftUI

struct PhaseBanner: View {
    let phase: SessionPhase

    var body: some View {
        Group {
            switch phase {
            case .countIn:
                label("Listen to the gong", Theme.gong)
            case .example:
                label("Watch and listen", Theme.upcoming)
            case .userTurn:
                label("Your turn", Theme.hit)
            }
        }
    }

    private func label(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.sans(18))
            .tracking(1.2)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(color.opacity(0.35), in: Capsule())
            .overlay(Capsule().stroke(color, lineWidth: 1.5))
            .id(text)
            .transition(.opacity)
    }
}

// MARK: - Speed control

/// Playback speed for the demo (§5.3 tempo scales). The scored run is always at
/// tempo, so this only ever appears on the watch screen.
struct SpeedPicker: View {
    @Binding var scale: Double
    var options: [Double] = [0.5, 0.75, 1.0]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let selected = abs(option - scale) < 0.01
                Button { scale = option } label: {
                    Text(label(option))
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(selected ? Theme.ink : Theme.copper)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .background {
                            Capsule().fill(selected ? Theme.copper : .clear)
                        }
                        .overlay(Capsule().strokeBorder(Theme.copper.opacity(selected ? 0 : 0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func label(_ value: Double) -> String {
        value == 1 ? "1×" : String(format: "%g×", value)
    }
}

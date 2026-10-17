//
//  TempoPicker.swift
//  Kotek
//
//  Tempo picker dropdown menu for practice session.
//
//  A gauge, not a metronome: the metronome click is gone (the kajar keeps the
//  pulse), and a metronome icon on the one control left read as a switch for
//  it. This sets speed, so it shows a speedometer.
//

import SwiftUI

struct TempoPicker: View {
    @Binding var tempoScale: Double

    var body: some View {
        Menu {
            ForEach(Theme.tempoScales, id: \.self) { scale in
                Button {
                    tempoScale = scale
                } label: {
                    if tempoScale == scale {
                        HStack {
                            Image(systemName: "checkmark")
                            Text(Theme.tempoLabel(scale)).tag(scale)
                        }
                    } else {
                        Text(Theme.tempoLabel(scale)).tag(scale)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.symbol(12, weight: .semibold))
                Text(Theme.tempoLabel(tempoScale))
                    .font(.sans(12, weight: .semibold))
                    .tracking(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.symbol(9, weight: .semibold))
            }
            .foregroundStyle(Theme.copper)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .overlay(
                Capsule().strokeBorder(Theme.copper.opacity(0.45), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .compositingGroup()
        .menuOrder(.fixed)
        .kajarOnChange(of: tempoScale)
        .accessibilityLabel("Tempo, \(Theme.tempoLabel(tempoScale))")
    }
}

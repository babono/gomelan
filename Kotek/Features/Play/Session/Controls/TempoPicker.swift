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
            AppMenuLabel(
                title: Theme.tempoLabel(tempoScale),
                systemImage: "gauge.with.dots.needle.67percent"
            )
        }
        .compositingGroup()
        .menuOrder(.fixed)
        .kajarOnChange(of: tempoScale)
        .accessibilityLabel("Tempo, \(Theme.tempoLabel(tempoScale))")
    }
}

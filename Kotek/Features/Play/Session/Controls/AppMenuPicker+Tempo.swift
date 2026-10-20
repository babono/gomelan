//
//  AppMenuPicker+Tempo.swift
//  Kotek
//
//  The tempo menu of the practice session.
//
//  A gauge, not a metronome: the metronome click is gone (the kajar keeps the
//  pulse), and a metronome icon on the one control left read as a switch for
//  it. This sets speed, so it shows a speedometer.
//

import SwiftUI

extension AppMenuPicker where Option == Double {
    static func tempo(_ tempoScale: Binding<Double>) -> AppMenuPicker {
        AppMenuPicker(
            options: Theme.tempoScales,
            selection: tempoScale,
            title: Theme.tempoLabel,
            label: "Tempo",
            systemImage: "gauge.with.dots.needle.67percent"
        )
    }
}

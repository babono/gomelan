//
//  TempoSectionView.swift
//  Kotek
//
//  Settings card for adjusting the default practice tempo.
//

import SwiftUI

struct TempoSectionView: View {
    @Bindable var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Tempo", selection: $app.tempoScale) {
                ForEach(Theme.tempoScales, id: \.self) { scale in
                    Text(Theme.tempoLabel(scale)).tag(scale)
                }
            }
            .pickerStyle(.segmented)
            .kajarOnChange(of: app.tempoScale)
            .frame(maxWidth: 400)

            Text(
                "Also on the practice screen, where it can be changed without stopping. Above 1× is faster than the figure is notated."
            )
            .font(.sans(13))
            .foregroundStyle(Theme.cream.opacity(0.75))
            .frame(maxWidth: 400)
        }
    }
}

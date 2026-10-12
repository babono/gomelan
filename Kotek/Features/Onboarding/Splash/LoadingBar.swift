//
//  LoadingBar.swift
//  Kotek
//
//  The splash's progress: a thin red line filling a card-coloured track. It
//  replaced the cream ProgressPill with the percentage written in it — the
//  revamp's splash has no number, only the line.
//

import SwiftUI

struct LoadingBar: View {
    var progress: Double

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(1, max(0, progress))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.deep)
                Capsule()
                    .fill(Theme.progress)
                    .frame(width: proxy.size.width * clamped)
            }
            .animation(.easeOut(duration: 0.25), value: clamped)
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
        .accessibilityValue("\(Int(min(1, max(0, progress)) * 100)) percent")
    }
}

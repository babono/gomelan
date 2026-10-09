//
//  MicSpectrumView.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import QuartzCore
import SwiftUI

/// A lightweight "spectrum" that pulses on each strike and decays between
/// them — a felt sense of the mic hearing something, not a real FFT plot.
struct MicSpectrumView: View {
    let micLevel: Float
    let micLevelTime: Double
    var height: CGFloat = 26

    /// A fixed, roughly gangsa-shaped relative envelope (bright fundamental,
    /// decaying inharmonic partials) so the bars look like a strike, not noise.
    private static let spectrumProfile: [Double] = [
        0.35, 0.9, 0.6, 0.45, 1.0, 0.5, 0.3, 0.7, 0.4, 0.55, 0.25
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            // micLevelTime is CACurrentMediaTime; convert both to a decay age.
            let age = max(0, CACurrentMediaTime() - micLevelTime)
            let level = Double(micLevel) * exp(-age / 0.45)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0 ..< 22, id: \.self) { i in
                    let profile = Self.spectrumProfile[i % Self.spectrumProfile.count]
                    let jitter = 0.8 + 0.2 * sin(now * 6 + Double(i))
                    let h = max(3, height * min(1, level * 3) * profile * jitter)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.copper.opacity(0.85))
                        .frame(width: 5, height: h)
                }
            }
            .frame(maxWidth: .infinity, minHeight: height, alignment: .bottomLeading)
        }
        .frame(height: height)
    }
}

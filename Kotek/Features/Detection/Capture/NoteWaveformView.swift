//
//  NoteWaveformView.swift
//  Kotek
//
//  Mirrored peak bars for a take, live or saved. `progress` draws a moving line
//  over it, like a player's playhead.
//

import SwiftUI

struct NoteWaveformView: View {
    let levels: [Float]
    /// 0…1 while playing, nil otherwise.
    var progress: Double?
    var tint: Color = Theme.cream

    /// Raw mic peaks of a quiet room are tiny; normalising by the loudest bar
    /// would blow that up into a full-height wall.
    private let minimumScale: Float = 0.05

    var body: some View {
        Canvas { context, size in
            guard !levels.isEmpty else { return }
            let scale = max(levels.max() ?? 0, minimumScale)
            let slot = size.width / CGFloat(levels.count)
            let barWidth = max(1, slot * 0.6)
            for (i, level) in levels.enumerated() {
                let height = max(2, CGFloat(level / scale) * size.height)
                let rect = CGRect(
                    x: CGFloat(i) * slot + (slot - barWidth) / 2,
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                let played = progress.map { Double(i) / Double(levels.count) < $0 } ?? true
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(tint.opacity(played ? 0.95 : 0.35))
                )
            }
            if let progress {
                let x = size.width * CGFloat(progress)
                context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(Theme.copper))
            }
        }
        .accessibilityHidden(true)
    }
}

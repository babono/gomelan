//
//  DetectionKeyOverlay.swift
//  Kotek
//
//  Live per-key probability tints and bounding rects overlaid on the camera feed.
//

import SwiftUI

struct DetectionKeyOverlay: View {
    let keys: [InstrumentKey]
    let scores: [Int: Double]
    let visionThreshold: Double
    let lastHitKey: Int?

    var body: some View {
        GeometryReader { geometry in
            ForEach(keys) { key in
                let prob = scores[key.index] ?? 0
                let isHit = prob >= visionThreshold
                let justFired = lastHitKey == key.index
                let rect = key.rect.rect(in: geometry.size)

                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        justFired ? Theme.accent : (isHit ? Color.green : .white.opacity(0.35)),
                        lineWidth: justFired ? 4 : (isHit ? 3 : 1.5)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.green.opacity(isHit ? 0.3 * prob : 0))
                    )
                    .overlay(alignment: .top) {
                        Text("\(key.index) · \(Int(prob * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(isHit ? .green : .white.opacity(0.7))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule())
                            .offset(y: -18)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .ignoresSafeArea()
    }
}

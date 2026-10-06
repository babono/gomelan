//
//  DetectionMarkerOverlay.swift
//  Kotek
//
//  Visualizer for retroreflective mallet tape tracking (blobs, bands, and extrapolated tip).
//

import SwiftUI

struct DetectionMarkerOverlay: View {
    let isFrontPOV: Bool
    let bandEdges: [Double]
    let roiTop: Double
    let markerFrame: MarkerFusion.Frame?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if isFrontPOV {
                    ForEach(Array(bandEdges.enumerated()), id: \.offset) { _, edge in
                        Rectangle()
                            .fill(Theme.copper.opacity(0.5))
                            .frame(width: 1, height: geometry.size.height)
                            .position(x: edge * geometry.size.width, y: geometry.size.height / 2)
                    }
                    if roiTop > 0 {
                        Rectangle()
                            .fill(.black.opacity(0.45))
                            .frame(height: roiTop * geometry.size.height)
                            .position(
                                x: geometry.size.width / 2,
                                y: roiTop * geometry.size.height / 2
                            )
                    }
                }
                if let frame = markerFrame {
                    ForEach(Array(frame.blobs.enumerated()), id: \.offset) { i, blob in
                        let r = CGRect(
                            x: blob.minX * geometry.size.width,
                            y: blob.minY * geometry.size.height,
                            width: blob.width * geometry.size.width,
                            height: blob.height * geometry.size.height
                        )
                        Rectangle()
                            .stroke(i == 0 ? Theme.accent : Theme.copper, lineWidth: 2)
                            .frame(width: max(r.width, 6), height: max(r.height, 6))
                            .position(x: r.midX, y: r.midY)
                    }
                    if let tip = frame.tip {
                        Path { path in
                            let p = CGPoint(
                                x: tip.x * geometry.size.width,
                                y: tip.y * geometry.size.height
                            )
                            path.move(to: CGPoint(x: p.x - 12, y: p.y))
                            path.addLine(to: CGPoint(x: p.x + 12, y: p.y))
                            path.move(to: CGPoint(x: p.x, y: p.y - 12))
                            path.addLine(to: CGPoint(x: p.x, y: p.y + 12))
                        }
                        .stroke(Theme.hit, lineWidth: 2)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

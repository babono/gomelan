//
//  FramingRegionView.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// The area every bilah has to sit inside. Everything outside it is dimmed, so
/// the frame reads as a window rather than as a decoration — and so it is
/// obvious when a bar is hanging out of it.
struct FramingRegionView: View {
    let region: NormalizedRect

    var body: some View {
        GeometryReader { geo in
            let rect = region.rect(in: geo.size)
            let shape = RoundedRectangle(cornerRadius: 14)

            ZStack {
                Color.black.opacity(0.42)
                    .reverseMask {
                        shape.frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }

                shape
                    .strokeBorder(
                        Theme.copper.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2, dash: [10, 7])
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Punch a hole in this view in the shape of `mask`.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            ZStack {
                Rectangle()
                mask().blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}

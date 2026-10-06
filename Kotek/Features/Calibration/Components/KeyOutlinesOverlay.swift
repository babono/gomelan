//
//  KeyOutlinesOverlay.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// Shared bilah key outlines overlay drawn over the camera preview.
/// Used during acoustic calibration and strike baseline verification.
struct KeyOutlinesOverlay: View {
    let keys: [InstrumentKey]
    var strokeColor: Color = Theme.copper.opacity(0.25)
    var lineWidth: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            ForEach(keys) { key in
                let rect = key.rect.rect(in: geo.size)
                RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                    .strokeBorder(strokeColor, lineWidth: lineWidth)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }
}

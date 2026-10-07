//
//  MagnifierLoupeView.swift
//  Kotek
//
//  Created by Dimas Nugraha on 05/10/26.
//

import SwiftUI

/// A CamScanner-style magnifier: shows a zoomed crop of the live camera around
/// the point being placed, with a crosshair, so masks can be positioned to the
/// pixel. Sampled from the same buffered frame the overlay maps against.
struct MagnifierLoupeView: View {
    let focus: CGPoint // overlay-normalised (0…1)
    let image: CGImage
    let bufferSize: CGSize
    let viewSize: CGSize
    var zoom: CGFloat = 2.6
    let diameter: CGFloat = 150

    var body: some View {
        ZStack {
            if let cropped {
                Image(decorative: cropped, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
            }
            // Crosshair at the exact placement point.
            Path { p in
                let c = diameter / 2
                p.move(to: CGPoint(x: c - 14, y: c))
                p.addLine(to: CGPoint(x: c + 14, y: c))
                p.move(to: CGPoint(x: c, y: c - 14))
                p.addLine(to: CGPoint(x: c, y: c + 14))
            }
            .stroke(Theme.copper, lineWidth: 1.5)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.copper, lineWidth: 2))
        .shadow(color: .black.opacity(0.55), radius: 6)
    }

    /// Crop the buffer image to the region under `focus`, sized so it fills the
    /// loupe at `zoom`. Uses CropMapper to project overlay space to buffer pixels.
    private var cropped: CGImage? {
        guard bufferSize.width > 0, bufferSize.height > 0,
              viewSize.width > 0, viewSize.height > 0
        else { return nil }
        let spanX = (diameter / zoom) / viewSize.width
        let spanY = (diameter / zoom) / viewSize.height
        let overlayRect = NormalizedRect(
            x: focus.x - spanX / 2,
            y: focus.y - spanY / 2,
            w: spanX,
            h: spanY
        )
        let rect = CropMapper.bufferRect(
            overlay: overlayRect,
            bufferSize: bufferSize,
            viewSize: viewSize
        )
        return MalletHitClassifier.crop(image, to: rect)
    }
}

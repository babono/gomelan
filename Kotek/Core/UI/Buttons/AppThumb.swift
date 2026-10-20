//
//  AppThumb.swift
//  Kotek
//
//  The thumb that slides under the chosen option of a toggle.
//

import SwiftUI

/// The HIG's lighter pill under the chosen label. The cream at low opacity
/// rather than the gold of a primary button, so gold stays the colour of a
/// screen's way on; the one place to change if that ever flips.
struct AppThumb<S: Shape>: View {
    let shape: S

    var body: some View {
        shape
            .fill(Theme.cream.opacity(0.18))
            .overlay(shape.stroke(Theme.cream.opacity(0.22), lineWidth: 0.5))
    }
}

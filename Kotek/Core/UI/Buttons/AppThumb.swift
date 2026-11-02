//
//  AppThumb.swift
//  Kotek
//
//  The thumb that slides under the chosen option of a toggle.
//

import SwiftUI

/// The HIG's lighter pill under the chosen label: white on the Krem track,
/// with a breath of shadow so it sits ON the track — the design system's
/// "Pemade | Kantilan". Not Merah, so the red stays the screen's way on —
/// except where the choice IS a colour: Polos / Sangsih fill it with the
/// voice's own (`AppSwitcher.tint`).
struct AppThumb<S: Shape>: View {
    let shape: S
    var fill: Color = Theme.surface

    var body: some View {
        shape
            .fill(fill)
            .shadow(color: Theme.ireng.opacity(0.12), radius: 2, y: 1)
    }
}

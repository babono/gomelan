//
//  OrnamentsView.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// The carved ornaments behind the title: three down each side, breathing.
/// Held out from the welcome screen at the designer's request, but preserved
/// intact so that its measured arrangement and animation rates are retained.
struct Ornaments: View {
    /// One ornament, at rest on its own side of the screen.
    struct Mark: Identifiable {
        let id: Int
        let art: Int
        let x: Double
        let y: Double
        let size: Double
        let rise: Double
        let risePeriod: Double
        let sway: Double
        let spinPeriod: Double
        let opacity: Double
    }

    private let marks: [Mark] = [
        // Left
        Mark(id: 0, art: 0, x: 0.08, y: 0.16, size: 58, rise: 16, risePeriod: 11, sway: 0.35, spinPeriod: 38, opacity: 0.50),
        Mark(id: 1, art: 1, x: 0.14, y: 0.48, size: 44, rise: 12, risePeriod: 8, sway: 0.30, spinPeriod: -29, opacity: 0.38),
        Mark(id: 2, art: 0, x: 0.06, y: 0.79, size: 66, rise: 19, risePeriod: 14, sway: 0.25, spinPeriod: 47, opacity: 0.45),
        // Right
        Mark(id: 3, art: 1, x: 0.90, y: 0.13, size: 62, rise: 18, risePeriod: 13, sway: 0.28, spinPeriod: -34, opacity: 0.46),
        Mark(id: 4, art: 0, x: 0.84, y: 0.45, size: 46, rise: 13, risePeriod: 9, sway: 0.32, spinPeriod: 26, opacity: 0.36),
        Mark(id: 5, art: 1, x: 0.92, y: 0.76, size: 54, rise: 15, risePeriod: 12, sway: 0.27, spinPeriod: -41, opacity: 0.44),
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(marks) { mark in
                DriftingMark(mark: mark, inverted: mark.id.isMultiple(of: 2))
                    .position(
                        x: mark.x * geo.size.width,
                        y: mark.y * geo.size.height
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

/// One ornament: turning, rising and swaying, all of it on the render server.
private struct DriftingMark: View {
    let mark: Ornaments.Mark
    let inverted: Bool

    @State private var spun = false
    @State private var risen = false
    @State private var swayed = false

    private var art: String { mark.art == 0 ? "ornament-1" : "ornament-2" }
    private var direction: Double { inverted ? -1 : 1 }
    private var swayBy: Double { mark.rise * mark.sway }

    var body: some View {
        Image(art)
            .resizable()
            .frame(width: mark.size, height: mark.size)
            .opacity(mark.opacity)
            .rotationEffect(
                .degrees(spun ? (mark.spinPeriod < 0 ? -360 : 360) : 0)
            )
            .animation(
                .linear(duration: abs(mark.spinPeriod))
                    .repeatForever(autoreverses: false),
                value: spun
            )
            .offset(y: (risen ? mark.rise : -mark.rise) * direction)
            .animation(
                .easeInOut(duration: mark.risePeriod / 2)
                    .repeatForever(autoreverses: true),
                value: risen
            )
            .offset(x: (swayed ? swayBy : -swayBy) * direction)
            .animation(
                .easeInOut(duration: mark.risePeriod * 1.6 / 2)
                    .repeatForever(autoreverses: true),
                value: swayed
            )
            .onAppear {
                spun = true
                risen = true
                swayed = true
            }
    }
}

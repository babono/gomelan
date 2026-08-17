//
//  WelcomeView.swift
//  gomelan
//
//  Entry screen (PRD §8), built to the Sangsih design: the name in Dream
//  Orphans over the drifting pattern, one cream key to press, and a pelawah
//  rising from the bottom edge.
//
//  Framing stays honest: this helps you take a first step, before a teacher —
//  never instead of one (§1).
//

import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height

            ZStack {
                Ornaments()

                VStack(spacing: 0) {
                    Spacer().frame(height: h * 0.08)

                    Text("Sangsih")
                        .font(.serif(min(76, h * 0.19)))
                        .foregroundStyle(Theme.cream)
                        .tracking(-0.5)

                    Spacer().frame(height: h * 0.09)

                    PillButton(title: "Enter", style: .filled, uppercase: false) {
                        app.begin()
                    }
                    .frame(width: 146)

                    Spacer()
                }

                // Anchored to the bottom edge and allowed to run off it, so the
                // instrument reads as continuing past the screen rather than
                // sitting on a shelf.
                VStack {
                    Spacer()
                    Pelawah()
                        .frame(width: min(470, proxy.size.width * 0.54), height: 142)
                        .offset(y: 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Ornaments

/// The spoked gold rosettes scattered behind the title.
///
/// Positions are fractions of the screen rather than the design's fixed pixels,
/// so the arrangement survives a different aspect ratio instead of clustering
/// in one corner. Drawn in a single Canvas — they are decoration, and a dozen
/// view identities for decoration is a dozen too many.
private struct Ornaments: View {
    /// x, y (fractions) and diameter in points.
    private let marks: [(x: Double, y: Double, d: Double)] = [
        (0.07, 0.10, 68), (0.86, 0.07, 74), (0.19, 0.38, 58),
        (0.76, 0.39, 62), (0.03, 0.72, 64), (0.92, 0.71, 70),
    ]

    var body: some View {
        Canvas { context, size in
            for mark in marks {
                let d = mark.d
                let rect = CGRect(x: mark.x * size.width, y: mark.y * size.height,
                                  width: d, height: d)
                let centre = CGPoint(x: rect.midX, y: rect.midY)

                // Spokes, radiating from a clear hub.
                for i in 0..<21 {
                    let angle = Double(i) / 21 * 2 * .pi
                    var path = Path()
                    path.move(to: CGPoint(x: centre.x + cos(angle) * d * 0.16,
                                          y: centre.y + sin(angle) * d * 0.16))
                    path.addLine(to: CGPoint(x: centre.x + cos(angle) * d * 0.5,
                                             y: centre.y + sin(angle) * d * 0.5))
                    context.stroke(path, with: .color(Theme.gold.opacity(0.5)), lineWidth: 1.2)
                }
                context.fill(
                    Path(ellipseIn: CGRect(x: centre.x - 6, y: centre.y - 6, width: 12, height: 12)),
                    with: .color(Theme.gold.opacity(0.85)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Pelawah

/// The carved teak frame with its row of bronze bilah — the app's own
/// instrument, drawn rather than photographed so it takes the palette.
struct Pelawah: View {
    var barCount = 10
    /// Which bar is lit cream instead of bronze, if any.
    var highlighted: Int? = 3

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack(alignment: .topLeading) {
                // Body: a shallow trapezium, wider at the top, like a real
                // pelawah seen slightly from above.
                Trapezium(inset: 0.045)
                    .fill(Theme.wood)
                    .frame(height: h * 0.46)
                    .offset(y: h * 0.54)

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: 0x6E4526))
                    .frame(height: h * 0.05)
                    .offset(y: h * 0.53)

                // Legs.
                ForEach([0.04, 0.905], id: \.self) { x in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(hex: 0x7A4A28))
                        .frame(width: w * 0.055, height: h * 0.6)
                        .offset(x: w * x, y: h * 0.4)
                }

                // Bilah.
                HStack(spacing: w * 0.015) {
                    ForEach(0..<barCount, id: \.self) { i in
                        let lit = i == highlighted
                        RoundedRectangle(cornerRadius: 5)
                            .fill(lit ? Theme.cream : Theme.bronze)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(lit ? Color(hex: 0xD6BC85) : Color(hex: 0xA98A58))
                                    .frame(height: h * 0.52 * 0.26)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
                .frame(width: w * 0.78, height: h * 0.52)
                .offset(x: w * 0.11)
            }
        }
    }
}

/// A rectangle whose bottom edge is narrower than its top.
private struct Trapezium: Shape {
    /// How far each bottom corner is drawn in, as a fraction of the width.
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = rect.width * inset
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - dx, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + dx, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

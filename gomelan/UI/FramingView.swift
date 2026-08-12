//
//  FramingView.swift
//  gomelan
//
//  Setup step 2/3 (PRD §3.2, §8). Mount the phone above the gangsa and settle
//  the stand until every bilah sits inside the frame. First-run setup is meant
//  to take ~15 seconds (§2).
//

import SwiftUI

struct FramingView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Frame the instrument",
                   backTitle: "Back",
                   onBack: { app.screen = .choosingKeyCount },
                   trailingText: "2 / 3",
                   tint: Theme.cream, accent: Theme.copper)

            ZStack {
                CameraPreview(session: camera.session)
                    .overlay(Color.black.opacity(0.35))

                // Framing guide: a soft-cornered dashed window, ~10% margin (§3.2).
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Theme.copper.opacity(0.55),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [9, 7]))
                    .padding(20)

                // Bilah preview: a graduated row that always fits the guide, kept
                // clear of the bottom caption.
                VStack(spacing: 0) {
                    BilahPreview(count: max(app.profile.keyCount, 1))
                        .padding(.horizontal, 48)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Color.clear.frame(height: 72)   // reserve the caption strip
                }
                .padding(20)

                // Bottom caption + advance, on a scrim so they read over the feed.
                VStack {
                    Spacer()
                    HStack {
                        SectionLabel("Scanning · hold steady", color: Theme.inkStone)
                        Spacer()
                        PillButton(title: "Continue", style: .outlined, tint: Theme.copper) {
                            app.framingConfirmed()
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.6)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .background(Theme.ink)
        .onAppear { camera.start() }
    }
}

/// A decorative, self-fitting row of graduated bilah — longest/lowest on the
/// left — so the count the user chose has a recognisable shape while framing.
private struct BilahPreview: View {
    let count: Int

    var body: some View {
        GeometryReader { g in
            let spacing: CGFloat = 12
            let gaps = CGFloat(max(count - 1, 0)) * spacing
            let barWidth = min(58, max(8, (g.size.width - gaps) / CGFloat(count)))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    let t = count > 1 ? CGFloat(i) / CGFloat(count - 1) : 0
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Theme.copper.opacity(0.5), lineWidth: 1))
                        .frame(width: barWidth, height: g.size.height * (1 - 0.42 * t))
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .center)
        }
    }
}

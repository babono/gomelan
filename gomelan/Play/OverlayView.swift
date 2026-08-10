//
//  OverlayView.swift
//  gomelan
//
//  The 2D guidance layer drawn over the live camera feed (PRD §5.2, §13.5).
//  Peripheral legibility is the constraint: large shapes, high contrast, no text
//  during play. Includes the bottom approach track.
//

import SwiftUI

struct OverlayView: View {
    let keys: [InstrumentKey]
    let states: [Int: KeyRenderState]
    let approachNotes: [ApproachNote]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                ForEach(keys) { key in
                    keyShape(key, in: size)
                }
                approachTrack(in: size)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Keys

    @ViewBuilder
    private func keyShape(_ key: InstrumentKey, in size: CGSize) -> some View {
        let rect = key.rect.rect(in: size)
        let state = states[key.index] ?? KeyRenderState()
        let shape = RoundedRectangle(cornerRadius: Theme.keyCornerRadius)

        ZStack(alignment: .bottom) {
            // Base Key Target Box (Idle state matching exact key outline)
            shape
                .stroke(Color.white.opacity(0.35), lineWidth: Theme.keyOutlineWidth)
                .background(
                    shape.fill(Color.black.opacity(0.2))
                )

            // Key index number badge in center
            Text("\(key.index)")
                .font(.system(size: min(rect.width, rect.height) * 0.35, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            // -------------------------------------------------------------
            // KEY-FITTED APPROACH FILL (Smooth Bottom-to-Top Fill)
            // Fills inside the exact key bar as the note approaches hit time.
            // -------------------------------------------------------------
            if state.fill > 0 && !state.strikeNow {
                let fill = max(0, min(1.0, state.fill))
                shape
                    .fill(
                        LinearGradient(
                            colors: [Theme.upcoming.opacity(0.85), Theme.upcoming.opacity(0.4)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: rect.height * fill)
                    .clipShape(shape)
            }

            // -------------------------------------------------------------
            // STRIKE NOW / HIT FLASH (Solid Key Fill & Outer Flash)
            // -------------------------------------------------------------
            if state.strikeNow {
                shape
                    .fill(Theme.upcoming)
                    .shadow(color: Theme.upcoming, radius: 8)

                shape
                    .stroke(Color.white, lineWidth: Theme.keyOutlineWidth + 2)
            }

            // Transient hit/miss flashes
            if let flash = state.flash {
                shape
                    .fill(flashColor(flash))
                    .shadow(color: flashColor(flash), radius: 10)
            }

            // Damp hint (dashed outline)
            if state.damp {
                shape
                    .stroke(style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .foregroundColor(.white)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    private func flashColor(_ kind: FlashKind) -> Color {
        switch kind {
        case .hit: return Theme.hit
        case .miss: return Theme.miss
        case .wrong: return Theme.wrong
        }
    }

    // MARK: - Approach track (§13.5)

    @ViewBuilder
    private func approachTrack(in size: CGSize) -> some View {
        let trackHeight = Theme.approachTrackHeight
        let y = size.height - trackHeight / 2
        let strikeX = size.width * Theme.strikeLineFraction

        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(height: trackHeight)

            // Fixed strike line.
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 3, height: trackHeight)
                .position(x: strikeX, y: trackHeight / 2)

            // Notes travelling right → left toward the strike line.
            ForEach(approachNotes) { note in
                Circle()
                    .fill(Theme.upcoming)
                    .frame(width: 22, height: 22)
                    .position(x: size.width * note.xFraction, y: trackHeight / 2)
            }
        }
        .frame(width: size.width, height: trackHeight)
        .position(x: size.width / 2, y: y)
    }
}

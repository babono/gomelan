//
//  OverlayView.swift
//  gomelan
//
//  The guidance layer drawn over the live camera feed (PRD §5.2, §13.5).
//  Peripheral legibility is the constraint: large shapes, high contrast, no text
//  during play. Idle bilah read as faint copper outlines; the key to strike
//  glows terracotta. The stroke timeline lives in PlayView, below this.
//

import SwiftUI

struct OverlayView: View {
    let keys: [InstrumentKey]
    let states: [Int: KeyRenderState]
    let approachNotes: [ApproachNote]
    /// Colotomic markers (gong/kempur/kemong/beat) travelling along the track,
    /// so the pulse structure reads on the same row as the note numbers.
    var trackMarkers: [TrackMarker] = []

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ForEach(keys) { key in
                keyShape(key, in: size)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func keyShape(_ key: InstrumentKey, in size: CGSize) -> some View {
        let rect = key.rect.rect(in: size)
        let state = states[key.index] ?? KeyRenderState()
        let shape = RoundedRectangle(cornerRadius: Theme.keyCornerRadius)

        ZStack {
            // 1. Static base key rect — ALWAYS present as a guide.
            ZStack(alignment: .bottom) {
                shape
                    .fill(Color.black.opacity(0.18))
                    .overlay(shape.strokeBorder(Theme.copper.opacity(0.4), lineWidth: 1.5))

                // Bilah label near the bottom of the base rect.
                Text(bilahLabel(key.index, count: keys.count))
                    .font(.serif(max(10, min(rect.width * 0.35, 18)), weight: .bold))
                    .foregroundStyle(Theme.copper.opacity(0.85))
                    .padding(.bottom, 8)
            }
            .frame(width: rect.width, height: rect.height)

            // 2. Approaching cue — SEPARATE outer outline contracting symmetrically from all 4 sides.
            if state.fill > 0 && !state.strikeNow {
                let fill = max(0, min(1, state.fill))
                let maxPadding: CGFloat = 16
                let currentPadding = (1.0 - fill) * maxPadding
                let outerShape = RoundedRectangle(cornerRadius: Theme.keyCornerRadius + currentPadding * 0.5)

                outerShape
                    .strokeBorder(Theme.copper.opacity(0.9), lineWidth: 1.2)
                    .frame(width: rect.width + currentPadding * 2, height: rect.height + currentPadding * 2)
            }

            // 3. Strike now cue — GLOWING OUTLINE ONLY (NO SOLID RECT FILL)
            if state.strikeNow {
                shape
                    .strokeBorder(Theme.cream, lineWidth: 2.5)
                    .shadow(color: Theme.copper.opacity(0.9), radius: 8)
                    .frame(width: rect.width, height: rect.height)
            }

            // 4. Transient user strike flash — SOLID FILLS ONLY ON USER STRIKE!
            if let flash = state.flash {
                shape
                    .fill(flashColor(flash))
                    .shadow(color: flashColor(flash), radius: 10)
                    .frame(width: rect.width, height: rect.height)
            }

            // 5. Damp hint (dashed outline on the previous key).
            if state.damp {
                shape
                    .strokeBorder(Theme.copper, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .frame(width: rect.width, height: rect.height)
            }
        }
        .position(x: rect.midX, y: rect.midY)
    }

    private func flashColor(_ kind: FlashKind) -> Color {
        switch kind {
        case .hitPerfect:
            return Theme.hit // Vibrant Emerald Green (#4CAF50)
        case .hitGood:
            return Theme.terracotta // Terracotta / Warm Amber (#B35433)
        case .wrongOrOffBeat:
            return Color(hex: 0xE2E8F0) // Pale White
        }
    }

    /// Colotomic markers read by size + weight rather than text, so they stay
    /// legible in the periphery: the gong is the largest, the beat a faint tick.
    @ViewBuilder
    private func markerShape(_ marker: TrackMarker) -> some View {
        switch marker.kind {
        case .gong:
            Circle().stroke(Theme.gong, lineWidth: 3).frame(width: 30, height: 30)
        case .kempur:
            Circle().stroke(Theme.kempur, lineWidth: 3).frame(width: 22, height: 22)
        case .kemong:
            Circle().stroke(Theme.kemong, lineWidth: 2).frame(width: 16, height: 16)
        case .beat:
            Circle().fill(.white.opacity(0.3)).frame(width: 5, height: 5)
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

            // Colotomic pulse markers, drawn under the note numbers.
            ForEach(trackMarkers) { marker in
                markerShape(marker)
                    .position(x: size.width * marker.xFraction, y: trackHeight / 2)
            }

            // Notes travelling right → left toward the strike line.
            ForEach(approachNotes) { note in
                ZStack {
                    Circle().fill(Theme.upcoming)
                    Text("\(note.keyIndex)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.75))
                }
                .frame(width: 22, height: 22)
                .position(x: size.width * note.xFraction, y: trackHeight / 2)
            }
        }
        .frame(width: size.width, height: trackHeight)
        .position(x: size.width / 2, y: y)
    }
}

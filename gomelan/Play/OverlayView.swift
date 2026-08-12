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
}

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
    let trackMarkers: [TrackMarker]
    
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                ForEach(keys) { key in
                    keyShape(key, in: size)
                }
                bottomTrack(in: size)
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
            //                .background(
            //                    shape.fill(Color.black.opacity(0.2))
            //                )
            
            // Key index number badge in center
            //            Text("\(key.index)")
            //                .font(.system(size: min(rect.width, rect.height) * 0.35, weight: .bold, design: .rounded))
            //                .foregroundStyle(.white.opacity(0.85))
            //                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            
            // -------------------------------------------------------------
            // KEY-FITTED APPROACH FILL (Smooth Bottom-to-Top Fill)
            // Fills inside the exact key bar as the note approaches hit time.
            // -------------------------------------------------------------
            if state.fill > 0 && !state.strikeNow {
                //                let fill = max(0, min(1.0, state.fill))
                shape
                    .fill(
                        LinearGradient(
                            colors: [Theme.upcoming.opacity(0.85), Theme.upcoming.opacity(0.4)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: rect.height * max(0, min(1, state.fill)))
                    .clipShape(shape)
            }
            
            if state.approachScale > 0 && !state.strikeNow {
                let scale = state.approachScale
                shape
                    .stroke(Theme.upcoming.opacity(0.9), lineWidth: 2.5)
                    .frame(width: rect.width * scale, height: rect.height * scale)
                    .position(x: rect.midX, y: rect.midY)
                    .opacity(0.3 + 0.7 * (1.6 - scale) / 0.6)
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
    private func bottomTrack(in size: CGSize) -> some View {
        let h = Theme.approachTrackHeight
        let y = size.height - h / 2
        let strikeX = size.width * Theme.strikeLineFraction
        
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.black.opacity(0.45))
                .frame(height: h)
            
            // Colotomic markers behind the numbers.
            ForEach(trackMarkers) { m in
                Circle()
                    .fill(markerColor(m.kind))
                    .frame(width: markerSize(m.kind), height: markerSize(m.kind))
                    .position(x: size.width * m.xFraction, y: h / 2)
            }
            
            // The strike line: where a note is due.
            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 3, height: h)
                .position(x: strikeX, y: h / 2)
            
            // Note numbers on the same row.
            ForEach(approachNotes) { note in
                ZStack {
                    Circle().fill(Theme.upcoming).frame(width: 28, height: 28)
                    Text("\(note.keyIndex)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                }
                .position(x: size.width * note.xFraction, y: h / 2)
            }
        }
        .frame(width: size.width, height: h)
        .position(x: size.width / 2, y: y)
    }
    
    private func markerSize(_ kind: TrackMarker.Kind) -> CGFloat {
        switch kind {
        case .gong: return 34
        case .kempur: return 22
        case .kemong: return 16
        case .beat: return 7
        }
    }
    
    private func markerColor(_ kind: TrackMarker.Kind) -> Color {
        switch kind {
        case .gong: return Theme.gong.opacity(0.95)
        case .kempur: return Theme.gong.opacity(0.55)
        case .kemong: return Color.white.opacity(0.45)
        case .beat: return Color.white.opacity(0.28)
        }
    }
}

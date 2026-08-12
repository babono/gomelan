//
//  NotesRiver.swift
//  gomelan
//
//  The scrolling score — a piano roll for kotekan. Time runs left along x, pitch
//  is the bilah on y, and the two halves keep their own colour, so the interlock
//  reads as one woven line:
//
//    · POLOS lands on the beat, SANGSIH answers between — two colours on the
//      same lanes, your half solid, your partner's ghosted.
//    · The colotomic pulse (gong / kempur / kemong / beat) runs underneath, and
//      gong and kempur strike a faint rule up through the notes, so you can see
//      the cycle the figure is hung on.
//    · Everything crosses one strike line: what sits on it is what sounds now.
//
//  Deliberately SMALL. The guidance you play from is the bilah lighting up on
//  the instrument (OverlayView); this is peripheral context — where you are in
//  the cycle, what is coming, how the two halves lock together. It is a strip,
//  not a stage.
//
//  Drawn in a single Canvas, and it reads the engine itself so a frame of
//  scrolling invalidates this strip alone rather than the screen around it.
//

import SwiftUI

struct NotesRiver: View {
    let engine: PlayEngine
    /// The bilah the figure actually uses — the lanes to draw. Passed in rather
    /// than derived from what is on screen, so the lanes never jump about.
    let keyRange: ClosedRange<Int>
    /// Total keys on the instrument, for the bilah labels ("1·").
    let keyCount: Int
    /// The half you are playing; your partner has the other one.
    let yourHalf: KotekanHalf

    private let pulseRowHeight: CGFloat = 16
    private let gutterWidth: CGFloat = 18

    private var rows: Int { max(1, keyRange.count) }
    private var laneHeight: CGFloat { min(14, max(9, 42 / CGFloat(rows))) }
    private var pitchBandHeight: CGFloat { CGFloat(rows) * laneHeight }
    private var trackHeight: CGFloat { pitchBandHeight + pulseRowHeight }

    var body: some View {
        //R Read in the body, NOT inside the draw closure: Observation registers
        //R the dependency while the body runs, so a read that only happens at
        //R draw time would never invalidate the view and the river would stall.
        let notes = engine.approachNotes
        let markers = engine.trackMarkers

        return Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
            let strikeX = size.width * Theme.strikeLineFraction
            draw(markers: markers, in: &ctx, size: size)
            draw(notes: notes, in: &ctx, size: size, strikeX: strikeX)

            // The strike line, across both bands.
            ctx.fill(Path(CGRect(x: strikeX - 1, y: 0, width: 2, height: trackHeight)),
                     with: .color(Theme.cream.opacity(0.85)))

            // Bilah gutter last, so the notes slide away underneath it.
            ctx.fill(Path(CGRect(x: 0, y: 0, width: gutterWidth + 6, height: pitchBandHeight)),
                     with: .linearGradient(Gradient(colors: [Theme.inkRaised,
                                                             Theme.inkRaised.opacity(0)]),
                                           startPoint: .zero,
                                           endPoint: CGPoint(x: gutterWidth + 6, y: 0)))
            for key in keyRange {
                guard let symbol = ctx.resolveSymbol(id: key) else { continue }
                ctx.draw(symbol, at: CGPoint(x: gutterWidth / 2, y: y(for: key) + laneHeight / 2))
            }
        } symbols: {
            ForEach(Array(keyRange), id: \.self) { key in
                Text(bilahLabel(key, count: keyCount))
                    .font(.serif(min(12, laneHeight * 0.8), weight: .bold))
                    .foregroundStyle(Theme.copper.opacity(0.8))
                    .tag(key)
            }
        }
        .frame(height: trackHeight)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.inkRaised.opacity(0.8))
        .overlay(alignment: .top) { Rectangle().fill(Theme.copper.opacity(0.2)).frame(height: 1) }
    }

    // MARK: - Drawing

    private func draw(markers: [TrackMarker], in ctx: inout GraphicsContext, size: CGSize) {
        let pulseY = pitchBandHeight + pulseRowHeight / 2
        for marker in markers {
            let x = marker.xFraction * size.width

            // The colotomic frame, ruled up through the notes.
            if let rule = ruleColor(marker.kind) {
                ctx.fill(Path(CGRect(x: x - 0.5, y: 0, width: 1, height: pitchBandHeight)),
                         with: .color(rule))
            }

            // The pulse itself: size and colour, never text.
            let dot: (CGFloat, Color, Bool) = switch marker.kind {
            case .gong:   (9, Theme.gong, true)
            case .kempur: (8, Theme.kempur, false)
            case .kemong: (6, Theme.kemong, false)
            case .beat:   (3, Theme.cream.opacity(0.3), true)
            }
            let circle = Path(ellipseIn: CGRect(x: x - dot.0 / 2, y: pulseY - dot.0 / 2,
                                                width: dot.0, height: dot.0))
            if dot.2 {
                ctx.fill(circle, with: .color(dot.1))
            } else {
                ctx.stroke(circle, with: .color(dot.1), lineWidth: 2)
            }
        }
    }

    private func draw(notes: [ApproachNote], in ctx: inout GraphicsContext,
                      size: CGSize, strikeX: CGFloat) {
        let blockHeight = laneHeight * 0.66
        for note in notes {
            let x = note.xFraction * size.width
            let width = max(8, note.widthFraction * size.width)
            guard x + width >= 0, x <= size.width else { continue }

            let rect = CGRect(x: x, y: y(for: note.keyIndex) + (laneHeight - blockHeight) / 2,
                              width: width, height: blockHeight)
            let block = Path(roundedRect: rect, cornerRadius: 2.5)
            let color = color(of: note)

            if note.voice == .yours {
                ctx.fill(block, with: .color(color.opacity(0.95)))
            } else {
                ctx.fill(block, with: .color(color.opacity(0.28)))
                ctx.stroke(block, with: .color(color.opacity(0.7)), lineWidth: 1)
            }

            // Sounding right now: outlined in cream, the same language as the
            // bilah on the instrument.
            if x <= strikeX, x + width >= strikeX {
                ctx.stroke(block, with: .color(Theme.cream.opacity(0.9)), lineWidth: 1.5)
            }
        }
    }

    // MARK: - Geometry and colour

    /// Top edge of a bilah's lane. Low keys sit at the bottom, as on the
    /// instrument in front of the player.
    private func y(for key: Int) -> CGFloat {
        let row = CGFloat(key - keyRange.lowerBound)
        return pitchBandHeight - (row + 1) * laneHeight
    }

    /// Your half in its own colour at full strength; your partner's ghosted, so
    /// you see it coming without mistaking it for a stroke of yours. Once a note
    /// of yours has been judged, its trail carries the verdict instead.
    private func color(of note: ApproachNote) -> Color {
        if let outcome = note.outcome {
            switch outcome {
            case .perfect: return Theme.hit
            case .good: return Theme.terracotta
            case .lateEarly, .wrongKey: return Theme.wrong
            case .miss: return Theme.miss
            }
        }
        let half = note.voice == .yours ? yourHalf : yourHalf.other
        return half == .polos ? Theme.polosVoice : Theme.sangsihVoice
    }

    /// Vertical rule for the colotomic frame; nil for a plain beat.
    private func ruleColor(_ kind: TrackMarker.Kind) -> Color? {
        switch kind {
        case .gong: return Theme.gong.opacity(0.26)
        case .kempur: return Theme.kempur.opacity(0.14)
        case .kemong: return nil
        case .beat: return nil
        }
    }
}

// MARK: - Legend

/// Which colour is which half. Static, so it lives outside the river's canvas —
/// worth the room on the demo screen, not during the run.
struct VoiceLegend: View {
    let yourHalf: KotekanHalf

    var body: some View {
        HStack(spacing: 12) {
            chip(yourHalf, label: "\(yourHalf.title) · you", solid: true)
            chip(yourHalf.other, label: yourHalf.other.title, solid: false)
            HStack(spacing: 5) {
                Circle().fill(Theme.gong).frame(width: 7, height: 7)
                Text("Gong").font(.sans(11)).foregroundStyle(Theme.inkStone)
            }
        }
    }

    private func chip(_ half: KotekanHalf, label: String, solid: Bool) -> some View {
        let color = half == .polos ? Theme.polosVoice : Theme.sangsihVoice
        return HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(solid ? 0.95 : 0.28))
                .overlay(RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(color.opacity(solid ? 0 : 0.7), lineWidth: 1))
                .frame(width: 12, height: 7)
            Text(label).font(.sans(11)).foregroundStyle(Theme.inkStone)
        }
    }
}

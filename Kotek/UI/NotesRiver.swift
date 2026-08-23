//
//  NotesRiver.swift
//  Kotek
//
//  The score: one gong-cycle-worth of the figure, laid out still, with a
//  playhead sweeping through it. Time runs left along x, pitch is the bilah on
//  y, and the two halves keep their own colour so the interlock reads as one
//  woven line:
//
//    · POLOS lands on the beat, SANGSIH answers between — two colours on the
//      same lanes, your half solid, your partner's ghosted.
//    · The colotomic pulse (gong / kempur / kajar) runs underneath, and gong and
//      kempur strike a faint rule up through the notes, so you can see where the
//      figure sits against the cycle.
//    · Each block carries its BILAH NUMBER. Tracing a block back to a row label
//      at the edge is a lookup, and a lookup is exactly the thing you do not
//      have time for while playing; the number belongs on the thing itself.
//
//  IT NO LONGER SCROLLS. Notes used to slide right to left across a fixed
//  strike line, which meant rendering three loops at once so the stream never
//  ran dry at the turn, and it read as a rhythm game — the figure never stayed
//  still long enough to be seen as a figure. A kotekan is a short fixed shape
//  you repeat until it is in your hands, so it is drawn as one, and the
//  playhead does the moving. The whole pattern is on screen at all times, which
//  is also what lets a player look ahead to the bar they are about to need.
//
//  Deliberately SMALL. The guidance you play from is the bilah lighting up on
//  the instrument (OverlayView); this is peripheral context. It is a strip, not
//  a stage.
//
//  Drawn in a single Canvas, and it reads the engine itself so a frame of the
//  playhead moving invalidates this strip alone rather than the screen around
//  it.
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
    /// Draw both halves at full strength and label both.
    ///
    /// For the picker's preview, where you have not chosen a side yet: ghosting
    /// one of them would be answering a question nobody has asked, and the
    /// whole point of the preview is to show how the two lock together.
    var bothHalves = false

    private let pulseRowHeight: CGFloat = 12
    private let sideInset: CGFloat = 10

    private var rows: Int { max(1, keyRange.count) }
    /// Taller lanes than the scrolling version could afford — a number has to
    /// fit inside a block now, and an 8pt block cannot hold one.
    ///
    /// Trimmed from a 20pt cap to 17. This is peripheral context on a screen
    /// whose subject is the instrument in front of you, and every point it takes
    /// is a point of camera. 17 still leaves a 14pt block, which holds a bilah
    /// number at the size below with room to spare.
    private var laneHeight: CGFloat { min(17, max(12, 84 / CGFloat(rows))) }
    private var pitchBandHeight: CGFloat { CGFloat(rows) * laneHeight }
    private var trackHeight: CGFloat { pitchBandHeight + pulseRowHeight }

    var body: some View {
        //R Read in the body, NOT inside the draw closure: Observation registers
        //R the dependency while the body runs, so a read that only happens at
        //R draw time would never invalidate the view and the strip would stall.
        let notes = engine.cycleNotes
        let markers = engine.trackMarkers
        let playhead = engine.playhead

        return Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
            let track = CGRect(x: sideInset, y: 0,
                               width: max(1, size.width - sideInset * 2),
                               height: pitchBandHeight)
            //R Resolved up front, not inside the note loop: passing a closure
            //R that reads `ctx` into a call that takes `&ctx` is an overlapping
            //R access and will not compile.
            var labels: [Int: GraphicsContext.ResolvedSymbol] = [:]
            for key in keyRange { labels[key] = ctx.resolveSymbol(id: key) }

            draw(markers: markers, in: &ctx, track: track)
            draw(notes: notes, in: &ctx, track: track, labels: labels)
            draw(playhead: playhead, in: &ctx, track: track)
        } symbols: {
            // One symbol per bilah, resolved once and stamped onto every block
            // that plays it — cheaper than resolving text per note, and there
            // are only ever a handful of distinct keys in a figure.
            ForEach(Array(keyRange), id: \.self) { key in
                Text(bilahLabel(key, count: keyCount))
                    .font(.serif(min(12, laneHeight * 0.62), weight: .bold))
                    .foregroundStyle(Theme.deep)
                    .tag(key)
            }
        }
        .frame(height: trackHeight)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Theme.inkRaised.opacity(0.8))
        .overlay(alignment: .top) { Rectangle().fill(Theme.copper.opacity(0.2)).frame(height: 1) }
    }

    // MARK: - Drawing

    private func draw(markers: [TrackMarker], in ctx: inout GraphicsContext, track: CGRect) {
        let pulseY = pitchBandHeight + pulseRowHeight / 2
        for marker in markers {
            let x = track.minX + marker.xFraction * track.width

            // The colotomic frame, ruled up through the notes.
            if let rule = ruleColor(marker.kind) {
                ctx.fill(Path(CGRect(x: x - 0.5, y: 0, width: 1, height: pitchBandHeight)),
                         with: .color(rule))
            }

            // The pulse itself: size and colour, never text.
            let dot: (CGFloat, Color, Bool) = switch marker.kind {
            case .gong:   (9, Theme.gong, true)
            case .kempur: (8, Theme.kempur, false)
            case .kajar:  (5, Theme.kajar, false)
            case .beat:   (3, Theme.cream.opacity(0.3), true)
            }
            let circle = Path(ellipseIn: CGRect(x: x - dot.0 / 2, y: pulseY - dot.0 / 2,
                                                width: dot.0, height: dot.0))
            if dot.2 {
                ctx.fill(circle, with: .color(dot.1))
            } else {
                ctx.stroke(circle, with: .color(dot.1), lineWidth: 1.5)
            }
        }
    }

    private func draw(notes: [CycleNote], in ctx: inout GraphicsContext, track: CGRect,
                      labels: [Int: GraphicsContext.ResolvedSymbol]) {
        let blockHeight = laneHeight - 3
        for note in notes {
            let x = track.minX + note.x * track.width
            // Wide enough to hold a digit even on a figure whose strokes are
            // short: the number is the point of the block.
            let width = max(blockHeight, note.width * track.width)
            let rect = CGRect(x: x, y: y(for: note.keyIndex) + (laneHeight - blockHeight) / 2,
                              width: width, height: blockHeight)
            let block = Path(roundedRect: rect, cornerRadius: 3)
            let color = color(of: note)

            if note.isUnison, bothHalves, note.outcome == nil {
                // Both halves land here together. Split down the middle rather
                // than stacked: the block keeps its full height, so it still
                // holds a number and still sits in one lane.
                var left = ctx
                left.clip(to: Path(CGRect(x: rect.minX, y: rect.minY,
                                          width: rect.width / 2, height: rect.height)))
                left.fill(block, with: .color(voiceColor(yourHalf).opacity(0.95)))

                var right = ctx
                right.clip(to: Path(CGRect(x: rect.midX, y: rect.minY,
                                           width: rect.width / 2, height: rect.height)))
                right.fill(block, with: .color(voiceColor(yourHalf.other).opacity(0.95)))
            } else if note.voice == .yours || bothHalves {
                ctx.fill(block, with: .color(color.opacity(0.95)))
            } else {
                // Your partner's strokes are context, not instruction: outlined
                // and unlabelled, so they never read as a bar to hit.
                ctx.fill(block, with: .color(color.opacity(0.22)))
                ctx.stroke(block, with: .color(color.opacity(0.6)), lineWidth: 1)
            }

            // Due right now: outlined in cream, the same language the bilah on
            // the instrument use.
            if note.isCurrent {
                ctx.stroke(block, with: .color(Theme.cream.opacity(0.95)), lineWidth: 2)
            }

            // The number, on your own strokes only — see above.
            if note.voice == .yours || bothHalves, let symbol = labels[note.keyIndex] {
                ctx.draw(symbol, at: CGPoint(x: rect.midX, y: rect.midY))
            }
        }
    }

    /// The sweep. A soft trail behind it so the direction of travel is legible
    /// on a strip this short — a bare 2pt line at 250 ms per slot reads as a
    /// stutter rather than a sweep.
    private func draw(playhead: Double, in ctx: inout GraphicsContext, track: CGRect) {
        let x = track.minX + playhead * track.width
        let trail = min(x - track.minX, track.width * 0.12)
        if trail > 1 {
            ctx.fill(Path(CGRect(x: x - trail, y: 0, width: trail, height: trackHeight)),
                     with: .linearGradient(Gradient(colors: [Theme.cream.opacity(0),
                                                             Theme.cream.opacity(0.10)]),
                                           startPoint: CGPoint(x: x - trail, y: 0),
                                           endPoint: CGPoint(x: x, y: 0)))
        }
        ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: trackHeight)),
                 with: .color(Theme.cream.opacity(0.9)))
    }

    // MARK: - Geometry and colour

    /// Top edge of a bilah's lane. Low keys sit at the bottom, as on the
    /// instrument in front of the player.
    private func y(for key: Int) -> CGFloat {
        let row = CGFloat(key - keyRange.lowerBound)
        return pitchBandHeight - (row + 1) * laneHeight
    }

    /// Your half in its own colour at full strength; your partner's ghosted, so
    /// you see it without mistaking it for a stroke of yours. Once a note of
    /// yours has been judged, it carries the verdict until the cycle turns.
    private func color(of note: CycleNote) -> Color {
        if let outcome = note.outcome {
            switch outcome {
            case .perfect: return Theme.hit
            case .good: return Theme.terracotta
            case .lateEarly, .wrongKey: return Theme.wrong
            case .miss: return Theme.miss
            }
        }
        return voiceColor(note.voice == .yours ? yourHalf : yourHalf.other)
    }

    private func voiceColor(_ half: KotekanHalf) -> Color {
        half == .polos ? Theme.polosVoice : Theme.sangsihVoice
    }

    /// Vertical rule for the colotomic frame; nil for a plain beat.
    private func ruleColor(_ kind: TrackMarker.Kind) -> Color? {
        switch kind {
        case .gong: return Theme.gong.opacity(0.26)
        case .kempur: return Theme.kempur.opacity(0.14)
        case .kajar: return nil
        case .beat: return nil
        }
    }
}

// MARK: - Voice mixer

/// The legend IS the mixer. Each colour names a voice on the score, and tapping
/// it silences that voice — so learning a half can start with your partner
/// alone and add your own back once the figure is in the hands, which is how
/// kotekan is taught anyway.
///
/// Muting never hides anything: a silenced voice still draws on the score and
/// still lights the bilah, so you can watch a part you have chosen not to hear.
///
/// The gong is not here. It is the frame the cycle is measured against, and a
/// figure with nothing to be early or late against cannot be practised.
struct VoiceMixer: View {
    let yourHalf: KotekanHalf
    /// Off by default: you are the one playing this half. Turning it on makes
    /// the app play along, which is how you check a figure you have half
    /// forgotten without leaving the screen.
    @Binding var yourVoiceAudible: Bool
    @Binding var partnerAudible: Bool

    var body: some View {
        HStack(spacing: 8) {
            chip(color: colour(for: yourHalf),
                 label: "\(yourHalf.title) · you",
                 isOn: $yourVoiceAudible)
            chip(color: colour(for: yourHalf.other),
                 label: yourHalf.other.title,
                 isOn: $partnerAudible)
        }
    }

    private func colour(for half: KotekanHalf) -> Color {
        half == .polos ? Theme.polosVoice : Theme.sangsihVoice
    }

    private func chip(color: Color, label: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(isOn.wrappedValue ? 0.95 : 0.15))
                    .overlay(RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(color.opacity(isOn.wrappedValue ? 0 : 0.6), lineWidth: 1))
                    .frame(width: 12, height: 8)

                Text(label)
                    .font(.sans(11, weight: .medium))
                    .foregroundStyle(isOn.wrappedValue ? Theme.cream : Theme.inkStone.opacity(0.7))

                Image(systemName: isOn.wrappedValue ? "speaker.wave.1.fill" : "speaker.slash.fill")
                    .font(.sans(9))
                    .foregroundStyle(isOn.wrappedValue ? color : Theme.inkStone.opacity(0.7))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(isOn.wrappedValue ? Theme.ink.opacity(0.55) : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.inkStone.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The card-sized score

/// One kotekan's shape, small enough to live inside a picker card.
///
/// Drawn straight from the figure rather than from a `PlayEngine`, which is the
/// whole point: only one card is ever playing, but EVERY card can show what its
/// figure looks like. A shape you can compare at a glance says more about a
/// kotekan than a sentence of prose about it does, which is why the cards no
/// longer carry a blurb.
///
/// No numbers and no pulse row. At six points a slot a bilah number is
/// illegible, and this is not something anybody plays from — it answers "what
/// does this figure look like", and the practice screen answers "what do I
/// strike next". Two different questions, two different drawings.
struct KotekanMiniScore: View {
    let kotekan: Kotekan
    /// The engine, when this figure is the one sounding — nil on every other
    /// card. Passed as the engine rather than as a playhead VALUE on purpose:
    /// a `Double` read out of it by the caller registers the caller's body as a
    /// dependency, and the caller here is a carousel of eight cards, a top bar
    /// and a footer. That rebuilt the entire screen sixty times a second, which
    /// is what made swiping feel like it was catching. Read it in here and the
    /// invalidation stops in here.
    var engine: PlayEngine?

    var body: some View {
        ZStack {
            blocks
            if let engine { Playhead(engine: engine) }
        }
    }

    /// The figure itself. Nothing observable in here, so it is drawn once and
    /// then left alone while the line above it moves.
    private var blocks: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
            let range = kotekan.voicedKeyRange
            let rows = CGFloat(max(1, range.count))
            let lane = size.height / rows
            let slots = max(1, kotekan.slotsPerCycle)
            let slotW = size.width / CGFloat(slots)
            let blockH = max(3, lane - 2)
            let blockW = max(3, slotW * 0.82)

            func y(_ key: Int) -> CGFloat {
                size.height - CGFloat(key - range.lowerBound + 1) * lane + (lane - blockH) / 2
            }

            func draw(_ key: Int, slot: Int, color: Color, half: Bool, rightHalf: Bool) {
                let rect = CGRect(x: CGFloat(slot) * slotW, y: y(key),
                                  width: blockW, height: blockH)
                let block = Path(roundedRect: rect, cornerRadius: 1.5)
                guard half else { ctx.fill(block, with: .color(color)); return }
                var layer = ctx
                layer.clip(to: Path(CGRect(x: rightHalf ? rect.midX : rect.minX, y: rect.minY,
                                           width: rect.width / 2, height: rect.height)))
                layer.fill(block, with: .color(color))
            }

            for slot in 0..<slots {
                let p = kotekan.polos[slot]
                let s = kotekan.sangsih[slot]

                // Same key, same slot — the telu family's shared anchor tone.
                // Split, for the reason NotesRiver splits it: two blocks in one
                // place means one of the halves is simply not drawn.
                if let p, p == s {
                    draw(p, slot: slot, color: Theme.polosVoice, half: true, rightHalf: false)
                    draw(p, slot: slot, color: Theme.sangsihVoice, half: true, rightHalf: true)
                    continue
                }
                if let p { draw(p, slot: slot, color: Theme.polosVoice, half: false, rightHalf: false) }
                if let s { draw(s, slot: slot, color: Theme.sangsihVoice, half: false, rightHalf: false) }
            }

        }
    }

    /// The sweep, alone in its own view and its own layer. One thin rectangle is
    /// the only thing that has any business being redrawn every frame.
    private struct Playhead: View {
        let engine: PlayEngine

        var body: some View {
            //R Read in the body, NOT in the draw closure: Observation registers
            //R the dependency while the body runs, so a read that only happens
            //R at draw time would never invalidate and the line would stall.
            let playhead = engine.playhead
            return Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
                let x = size.width * min(1, max(0, playhead))
                ctx.fill(Path(CGRect(x: x - 0.75, y: 0, width: 1.5, height: size.height)),
                         with: .color(Theme.cream.opacity(0.85)))
            }
        }
    }
}

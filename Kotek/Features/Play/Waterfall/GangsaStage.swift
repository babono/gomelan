//
//  GangsaStage.swift
//  Kotek
//
//  The drawn gangsa plus what to light on it this frame, read from one
//  engine. Shared by the solo waterfall and by each lane of one-screen coop.
//

import SwiftUI

/// The instrument plus what to light on it this frame. Its own view so the
/// per-frame cue rebuild redraws the gangsa and nothing around it.
struct GangsaStage: View {
    let engine: PlayEngine
    let layout: GangsaLayout
    let tilted: Bool
    /// The bar a sensor fired on and how long ago, given the engine's
    /// `renderNow` — nil when none did in the last moment. A closure,
    /// evaluated in this body, so the per-frame read stays in here too.
    var sensedStrike: (Double) -> (key: Int, age: Double)? = { _ in nil }

    var body: some View {
        let figure = figure
        GangsaView(layout: layout, cues: figure.cues, mallet: figure.mallet, damper: figure.damper, tilted: tilted)
    }

    private var figure: (cues: [Int: BilahCue], mallet: HandCue?, damper: HandCue?) {
        var cues: [Int: BilahCue] = [:]
        var mallet: HandCue?
        var damper: HandCue?
        func struck(_ key: Int, age: Double) {
            let earlier = cues[key]?.struckAge ?? .infinity
            cues[key, default: BilahCue()].struckAge = min(earlier, age)
        }
        // A hit rings its bar even without a sensor behind it (coop). The
        // verdict itself glows in the lane above, not on the bar.
        for (key, flash) in engine.keyFlashes where flash.result.isHit {
            struck(key, age: flash.age)
        }

        // Damp: on the moment a note ends — when its falling damp tile
        // reaches the bar — and held for as long as that tile takes to pass
        // (the note's own length, 90…400 ms). It no longer waits for the next
        // stroke: a note before a rest is damped too, as it is on a real
        // gangsa, where the hand stops each bilah once its note is done.
        //
        // It once faded in a full beat early and out over 0.6 of one after,
        // and lit bars during rests and while they were still to be struck.
        // The falling tile gives the warning; the bar only has to say "now".
        //
        // Unlike the strike cue it does not vanish when you hit: it is the
        // left hand's moment, not the right's.
        //
        // The same walk gives the mallet its notes: the right hand is a guide
        // too, carried from stroke to stroke so it lands as the block does.
        let beat = engine.beatLengthMs
        if beat > 0 {
            // Four beats each way, so a hand is still found across a rest and
            // keeps standing on its last bar instead of vanishing.
            let notes = engine.fallingNotes(aheadMs: max(GangsaHands.travelMs, beat * 4), behindMs: beat * 4)
                .filter { $0.voice == .yours }
                .sorted { $0.msAhead < $1.msAhead }
            var damps: [(key: Int, ms: Double, hold: Double)] = []
            for note in notes {
                guard note.dampsAfter else { continue }
                let hold = min(max(note.durationMs, 90), 400)
                let held = -(note.msAhead + note.durationMs)
                damps.append((note.keyIndex, note.msAhead + note.durationMs, hold))
                // Eased over 90 ms each way so the bar visibly shrinks
                // into the pinch and back, instead of popping, and the thumb's
                // turn onto it can be seen (60 ms was a blink).
                let damp = min(1, held / 90, (hold - held) / 90)
                if damp > 0 {
                    let earlier = cues[note.keyIndex]?.damp ?? 0
                    cues[note.keyIndex, default: BilahCue()].damp = max(earlier, damp)
                }
            }
            // One hump per stroke, spread over the whole gap to the next, so the
            // mallet leaves the bar once and comes down once. It had a small
            // bounce off each bar and then the hop to the next in the last
            // 320 ms; over any gap past ~400 ms that was a tap, a rest, and
            // then the real stroke — which looked like hitting twice.
            mallet = Self.carriage(notes.map { ($0.keyIndex, $0.msAhead, 0) }).map { c in
                let lift = if c.from == c.to, c.since == nil {
                    0.7 * (1 - c.travel * c.travel) // lowering onto the first bar
                } else if let hump = c.phase {
                    0.7 * sin(.pi * hump)
                } else {
                    0.2 // nothing to land on yet: hold clear of the bar
                }
                return HandCue(from: c.from, to: c.to, travel: c.travel, pose: lift)
            }
            damper = Self.carriage(damps).map { c in
                HandCue(
                    from: c.from,
                    to: c.to,
                    travel: c.travel,
                    pose: cues.values.map(\.damp).max() ?? 0
                )
            }
        }

        // The raw sensor, before any judging — so a dead piezo is obvious.
        if let sensed = sensedStrike(engine.renderNow) {
            struck(sensed.key, age: sensed.age)
        }
        return (cues, mallet, damper)
    }

    /// A hand between two timed strokes: the last one at or before now and the
    /// next after it. It stays on the last bar, then crosses to the next over
    /// the last `travelMs` before it (or the gap, if shorter, less `hold`, the
    /// time the last stroke keeps it there — so a run of fast notes never
    /// stops, and a pinch is never dragged along the bars).
    ///
    /// The mallet was a copy per bar, fading in over each note and out after,
    /// and the damp hand likewise; they read as things blinking on, not as a
    /// hand moving. Nil only when no stroke is anywhere near.
    private static func carriage(
        _ events: [(key: Int, ms: Double, hold: Double)]
    ) -> (from: Int, to: Int, travel: Double, since: Double?, phase: Double?)? {
        let prev = events.last { $0.ms <= 0 }
        let next = events.first { $0.ms > 0 }
        switch (prev, next) {
        case (nil, nil):
            return nil
        case let (p?, nil):
            return (p.key, p.key, 0, -p.ms, nil)
        case let (nil, n?):
            // Nothing before it: waiting over the first bar.
            return (n.key, n.key, max(0, 1 - n.ms / GangsaHands.travelMs), nil, nil)
        case let (p?, n?):
            let crossing = max(40, min(n.ms - p.ms - p.hold, GangsaHands.travelMs))
            return (p.key, n.key, n.ms < crossing ? 1 - n.ms / crossing : 0, -p.ms, -p.ms / (n.ms - p.ms))
        }
    }
}

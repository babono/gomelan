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
        GangsaView(layout: layout, cues: cues, tilted: tilted)
    }

    private var cues: [Int: BilahCue] {
        var cues: [Int: BilahCue] = [:]
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
        let beat = engine.beatLengthMs
        if beat > 0 {
            for note in engine.fallingNotes(aheadMs: 0, behindMs: beat * 2)
                where note.voice == .yours && note.dampsAfter
            {
                let hold = min(max(note.durationMs, 90), 400)
                let held = -(note.msAhead + note.durationMs)
                // Eased over 60 ms each way so the bar visibly shrinks
                // into the pinch and back, instead of popping.
                let damp = min(1, held / 60, (hold - held) / 60)
                if damp > 0 {
                    let earlier = cues[note.keyIndex]?.damp ?? 0
                    cues[note.keyIndex, default: BilahCue()].damp = max(earlier, damp)
                }
            }
        }

        // The raw sensor, before any judging — so a dead piezo is obvious.
        if let sensed = sensedStrike(engine.renderNow) {
            struck(sensed.key, age: sensed.age)
        }
        return cues
    }
}

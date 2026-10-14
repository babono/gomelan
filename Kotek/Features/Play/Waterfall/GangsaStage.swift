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

        // Damp: on in the SAME frame as the strike cue — when the paired stroke
        // is due — and held for the span the engine holds that cue
        // (`tickUserTurnCue`: 55% of the gap to the next stroke, 90…400 ms).
        // "Hit this, pinch that" is one instruction, so it lights as one.
        //
        // It used to fade in a full beat early and out over 0.6 of one after,
        // peaking at the due instant. With strokes a slot apart that window
        // reached back to the previous stroke, so the red was always already
        // up before the strike cue appeared, slid onto the next bar early, lit
        // during rests, and could turn a bar red while it was still the one to
        // strike. The falling cue already gives the warning; the bar only has
        // to say "now".
        //
        // Unlike the strike cue it does not vanish when you hit: the moment
        // after the stroke is exactly when the left hand is pinching.
        let beat = engine.beatLengthMs
        if beat > 0 {
            let yours = engine.fallingNotes(aheadMs: beat * 4, behindMs: 400)
                .filter { $0.voice == .yours }
                .sorted { $0.msAhead < $1.msAhead }
            if let i = yours.lastIndex(where: { $0.msAhead <= 0 }),
               let key = yours[i].dampKey
            {
                let gap = i + 1 < yours.count ? yours[i + 1].msAhead - yours[i].msAhead : beat
                let hold = min(max(gap * 0.55, 90), 400)
                // Eased over 60 ms each way so the bar visibly shrinks
                // into the pinch and back, instead of popping.
                let held = -yours[i].msAhead
                let damp = min(1, held / 60, (hold - held) / 60)
                if damp > 0 {
                    cues[key, default: BilahCue()].damp = damp
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

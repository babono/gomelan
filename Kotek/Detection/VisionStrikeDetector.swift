//
//  VisionStrikeDetector.swift
//  Kotek
//
//  Turns a continuous stream of per-key hit probabilities into discrete strike
//  events — so vision can trigger itself, with no audio onset involved. That
//  makes detection immune to background noise (the audio trigger's weak point).
//
//  Each key is a Schmitt trigger: it fires when its probability rises above
//  `enter`, then must fall back before it can fire again. The hysteresis stops a
//  mallet resting on a key from firing every frame.
//
//  TWO THINGS MAKE IT USABLE ON A REAL FIGURE.
//
//  A RELATIVE DIP, not just an absolute floor. Re-arming only below 0.30 is
//  what made repeated strokes on one bilah go missing: a mallet bouncing on the
//  same bar at 250ms lifts a little, not a lot, and the score often never got
//  near 0.30 — so the second stroke of a 7→7 never fired. It re-arms on a fall
//  from its own peak as well, which is what a bounce actually looks like.
//
//  EXPECTATION. This is not open-set recognition: the engine knows which bilah
//  is due, so the bar for that one is set lower and the bar for the rest is set
//  higher than a single threshold could be. A marginal sighting on the key you
//  were about to play is almost certainly you playing it; the same sighting on a
//  key nothing is due on is almost certainly a hand passing over. One threshold
//  had to be a compromise between those and was wrong for both.
//

import Foundation

/// The numbers both screens that watch for strikes have to agree on.
///
/// They did not. Test Detection had its own corroboration window, its own veto
/// setting, and a slider that drove thresholds the play screen did not use —
/// so tuning on the screen built for tuning taught you nothing about a session.
/// Anything shared between the two lives here now, and the divergence has to be
/// deliberate rather than accidental.
nonisolated enum Detection {
    /// How far from a sighting the ear may find the attack that goes with it.
    /// Generous on purpose: vision leads the strike, so the onset arrives after
    /// the sighting, and a window too tight vetoes real strokes — which is the
    /// one failure a veto must never have.
    static let corroborationWindow: Double = 0.15

    /// The bar a crop must clear for an EAR-triggered event to accept it as the
    /// key, given the bar vision uses to trigger itself.
    ///
    /// Deliberately lower. An ear-triggered event already has a sound behind
    /// it, so vision only has to name the bilah — it does not also have to
    /// decide whether anything happened, which is the harder half and the one
    /// the self-trigger bar is set for.
    static func namingThreshold(from trigger: Double) -> Double { trigger * 0.9 }
}

final class VisionStrikeDetector {

    /// Rising-edge threshold for a key nothing is due on.
    var enter = 0.55
    /// Rising-edge threshold for the key the engine says is due. Lower, because
    /// the cost of being wrong is much lower: a false positive here is a note
    /// the player was about to play anyway.
    var enterExpected = 0.38
    /// Re-arm floor: below this, a key is ready again whatever it has been doing.
    var exit = 0.30
    /// Re-arm on a fall of this much from the peak since firing — the bounce
    /// between two strokes on one bar, which rarely reaches `exit`.
    var relativeDip = 0.12
    /// Never re-arm sooner than this. Caps the rate at about eight strokes a
    /// second, which is past what anyone plays and well inside the 250ms a
    /// bundled figure leaves between strokes.
    var minRearmSeconds = 0.09

    /// Set all three bars from the one number a player can actually reach.
    ///
    /// The slider on Test Detection is the only detection control anyone tunes,
    /// and the play screen used to ignore it — it carried its own hardcoded
    /// 0.55 and 0.38, so the slider moved a threshold that governed nothing you
    /// practise with. One call, both screens.
    ///
    /// `relativeDip` rides along because it is not a free-standing preference —
    /// it is THE number that decides whether a bar struck twice in a row
    /// registers twice, and it was hardcoded here while every other bar moved
    /// with the slider. So the one control anybody tunes governed everything
    /// about detection except its most-reported failure.
    func apply(threshold: Double, relativeDip: Double? = nil) {
        if let relativeDip { self.relativeDip = relativeDip }
        enter = threshold
        //R Seven tenths, the ratio the play screen was already using between
        //R its two hardcoded bars. The expected key is easier to trigger; see
        //R the note about expectation above.
        enterExpected = threshold * 0.7
        //R Re-arm well below the trigger so one strike cannot fire twice. The
        //R relative dip is what actually clears between repeated strokes.
        exit = threshold * 0.6
    }

    private struct KeyState {
        var armed = true
        var firedAt: Double = 0
        /// Highest score seen since firing, so the dip is measured from the top
        /// of the stroke rather than from the threshold.
        var peak: Double = 0
    }

    private var states: [Int: KeyState] = [:]

    /// Feed the latest per-key scores; returns the keys that *just* crossed into
    /// a hit this frame (usually zero or one).
    ///
    /// - Parameter expecting: the bilah the figure is asking for right now, if
    ///   any. See the note about expectation above.
    func process(scores: [Int: Double], expecting: Int? = nil, now: Double) -> [Int] {
        var fired: [Int] = []
        for (key, p) in scores {
            var state = states[key] ?? KeyState()

            if state.armed {
                if p >= (key == expecting ? enterExpected : enter) {
                    fired.append(key)
                    state.armed = false
                    state.firedAt = now
                    state.peak = p
                }
            } else {
                state.peak = max(state.peak, p)
                let dipped = p <= exit || p <= state.peak - relativeDip
                if dipped, now - state.firedAt >= minRearmSeconds { state.armed = true }
            }

            states[key] = state
        }
        return fired
    }

    func reset() {
        states.removeAll(keepingCapacity: true)
    }
}

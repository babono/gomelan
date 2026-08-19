//
//  VisionStrikeDetector.swift
//  Kotek
//
//  Turns a continuous stream of per-key hit probabilities into discrete strike
//  events — so vision can trigger itself, with no audio onset involved. That
//  makes detection immune to background noise (the audio trigger's weak point).
//
//  Each key is a Schmitt trigger: it fires when its probability rises above
//  `enter`, then must fall back below `exit` before it can fire again. The
//  hysteresis gap does two jobs: it stops a mallet resting on a key from firing
//  every frame, and it separates genuine repeated strikes (the probability dips
//  as the mallet lifts between hits).
//

import Foundation

final class VisionStrikeDetector {

    /// Rising-edge threshold: probability must exceed this to count as a strike.
    var enter = 0.50
    /// Re-arm threshold: must drop below this before the same key can fire again.
    var exit = 0.30

    /// Per key: is it armed (ready to fire)? Absent == armed.
    private var armed: [Int: Bool] = [:]

    /// Feed the latest per-key scores; returns the keys that *just* crossed into
    /// a hit this frame (usually zero or one).
    func process(scores: [Int: Double]) -> [Int] {
        var fired: [Int] = []
        for (key, p) in scores {
            let isArmed = armed[key] ?? true
            if isArmed, p >= enter {
                fired.append(key)
                armed[key] = false
            } else if !isArmed, p <= exit {
                armed[key] = true
            }
        }
        return fired
    }

    func reset() {
        armed.removeAll(keepingCapacity: true)
    }
}

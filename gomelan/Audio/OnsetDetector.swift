//
//  OnsetDetector.swift
//  gomelan
//
//  Spectral-flux onset detection (PRD §6.3). Flux — the sum of positive
//  bin-to-bin increases between successive spectra — rises sharply on a new
//  strike but stays flat during a note's long decay, so a previous key's sustain
//  won't trigger a false onset.
//
//  Validated parameters from §6.3: flux threshold 0.18 normalised, refractory
//  period 80ms.
//

import Foundation

final class OnsetDetector {
    /// Normalised flux threshold above which a frame is considered an onset.
    var threshold: Float = 0.28
    /// Minimum total energy required to trigger an onset (filters ambient room noise/silence).
    var minEnergy: Float = 1.8
    /// Minimum time between onsets.
    var refractorySeconds: Double = 0.150

    private var previousSpectrum: [Float]?
    private var lastOnsetTime: Double = -.greatestFiniteMagnitude

    // Dynamic noise floor adaptation
    private var noiseFloorSamples: [Float] = []
    private var isCalibratingNoise = false

    func reset() {
        previousSpectrum = nil
        lastOnsetTime = -.greatestFiniteMagnitude
        noiseFloorSamples.removeAll()
        isCalibratingNoise = true
    }

    /// Feed a magnitude spectrum captured at `time` (seconds). Returns true if
    /// this frame is an onset.
    func process(spectrum: [Float], time: Double) -> Bool {
        defer { previousSpectrum = spectrum }

        var flux: Float = 0
        var energy: Float = 0
        if let previous = previousSpectrum, previous.count == spectrum.count {
            for i in 0..<spectrum.count {
                let diff = spectrum[i] - previous[i]
                if diff > 0 { flux += diff }
                energy += spectrum[i]
            }
        } else {
            for i in 0..<spectrum.count { energy += spectrum[i] }
        }

        // Measure ambient room noise during the first 4 frames after reset
        if isCalibratingNoise {
            noiseFloorSamples.append(energy)
            if noiseFloorSamples.count >= 4 {
                let avgNoise = noiseFloorSamples.reduce(0, +) / Float(noiseFloorSamples.count)
                minEnergy = max(1.8, avgNoise * 2.2)
                isCalibratingNoise = false
            }
            return false
        }

        // Ignore quiet frames below dynamic ambient energy floor
        guard energy >= minEnergy else { return false }

        // Normalise by the current frame's energy so loud and quiet strikes are treated alike.
        let normalisedFlux = energy > 0 ? flux / energy : 0

        guard normalisedFlux >= threshold else { return false }
        guard time - lastOnsetTime >= refractorySeconds else { return false }

        lastOnsetTime = time
        return true
    }
}

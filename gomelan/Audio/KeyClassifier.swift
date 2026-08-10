//
//  KeyClassifier.swift
//  gomelan
//
//  Identifies which calibrated key was struck (PRD §6.3). §6.3 established that
//  keys on this instrument are reliably separable by fundamental alone (closest
//  separation 126 cents, need ~60 to be safe); the harmonic profile is kept as a
//  tiebreaker.
//

import Foundation

struct KeyMatch {
    let keyIndex: Int
    let fundamentalHz: Double
    let confidence: Double
}

final class KeyClassifier {
    /// Fundamental search band covering low to high gangsa keys (Pemade & Kantilan).
    /// Starts at 275 Hz to completely exclude low-frequency room/mic rumble (e.g. 245 Hz AC noise).
    var searchBandHz: ClosedRange<Double> = 275...3500

    /// Minimum peak magnitude in FFT spectrum required to consider a peak valid (filters room noise).
    var minPeakMagnitude: Float = 0.04

    /// Minimum peak prominence ratio: peak magnitude must be at least 2.0x the average bin magnitude in search band.
    var minProminenceRatio: Float = 2.0

    private let fft: FFTProcessor
    private let sampleRate: Double
    private var keys: [InstrumentKey]

    init(fft: FFTProcessor, sampleRate: Double, keys: [InstrumentKey]) {
        self.fft = fft
        self.sampleRate = sampleRate
        self.keys = keys
    }

    func updateKeys(_ keys: [InstrumentKey]) { self.keys = keys }

    /// Classify a magnitude spectrum captured just after an onset.
    func classify(spectrum: [Float]) -> KeyMatch? {
        guard !keys.isEmpty else { return nil }
        guard let fundamental = fundamental(spectrum: spectrum) else { return nil }

        // Nearest-neighbour match on fundamental, measured in cents so the metric
        // matches pitch perception rather than raw Hz.
        var best: (key: InstrumentKey, cents: Double)?
        for key in keys {
            let cents = abs(1200 * log2(fundamental / key.fundamentalHz))
            if best == nil || cents < best!.cents {
                best = (key, cents)
            }
        }
        guard let match = best else { return nil }

        // Confidence: 1.0 at a perfect match, decaying to 0 at ~120 cents (about
        // the closest key separation on this instrument).
        let confidence = max(0, 1 - match.cents / 120)
        return KeyMatch(keyIndex: match.key.index,
                        fundamentalHz: fundamental,
                        confidence: confidence)
    }

    /// Peak-picking fundamental estimate within the search band. Exposed so the
    /// calibration flow can record raw pitches without matching against keys.
    func fundamental(spectrum: [Float]) -> Double? {
        let lowBin = max(1, fft.bin(forFrequency: searchBandHz.lowerBound, sampleRate: sampleRate))
        let highBin = min(spectrum.count - 1, fft.bin(forFrequency: searchBandHz.upperBound, sampleRate: sampleRate))
        guard lowBin < highBin else { return nil }

        var peakBin = lowBin
        var maxWeightedValue: Float = 0
        var totalMagnitude: Float = 0

        for bin in lowBin...highBin {
            let mag = spectrum[bin]
            totalMagnitude += mag
            let freq = fft.frequency(ofBin: bin, sampleRate: sampleRate)
            // Weighting: slightly favors metallic frequencies so low room rumble doesn't overshadow key hits
            let weight = Float(sqrt(max(1.0, freq / 275.0)))
            let weighted = mag * weight
            if weighted > maxWeightedValue {
                maxWeightedValue = weighted
                peakBin = bin
            }
        }
        let peakValue = spectrum[peakBin]
        guard peakValue >= minPeakMagnitude else { return nil }

        let count = Float(highBin - lowBin + 1)
        let avgMagnitude = totalMagnitude / count
        guard avgMagnitude > 0 else { return nil }

        // Prominence check: genuine metallic key ringing has a sharp peak standing out above the spectrum floor
        let prominence = peakValue / avgMagnitude
        guard prominence >= minProminenceRatio else { return nil }

        // Parabolic interpolation around the peak for sub-bin accuracy.
        let refined = interpolatedBin(spectrum: spectrum, peakBin: peakBin)
        return fft.frequency(ofBin: 0, sampleRate: sampleRate) + refined * sampleRate / Double(fft.size)
    }

    private func interpolatedBin(spectrum: [Float], peakBin: Int) -> Double {
        guard peakBin > 0, peakBin < spectrum.count - 1 else { return Double(peakBin) }
        let a = Double(spectrum[peakBin - 1])
        let b = Double(spectrum[peakBin])
        let c = Double(spectrum[peakBin + 1])
        let denom = a - 2 * b + c
        guard denom != 0 else { return Double(peakBin) }
        let delta = 0.5 * (a - c) / denom
        return Double(peakBin) + delta
    }
}

//
//  DSPConfig.swift
//  gomelan
//
//  Direct mirror of `Config` in algorithm/gamelan_dsp.py. Every value here has a
//  counterpart there, and the two must not drift — the Python notebook is the
//  reference implementation and these constants were measured, not guessed.
//
//  Window sizes are in SAMPLES, so their duration depends on `sampleRate`.
//  At 44100: onsetWindow 1024 = 23ms, onsetHop 256 = 5.8ms, fpWindow 4096 = 93ms.
//

import Foundation

struct DSPConfig: Equatable {

    // MARK: STFT for onset detection
    var sampleRate: Double = 44100
    var onsetWindow: Int = 1024
    var onsetHop: Int = 256

    // MARK: Onset peak picking
    /// Ignore rumble / handling noise below this.
    var fluxFloorHz: Double = 150
    /// Window for the adaptive threshold.
    var medianLengthSeconds: Double = 0.20
    /// How far above the local median counts as a hit.
    var threshMultiplier: Float = 1.6
    /// Absolute floor, guards against silence. Relative to the running flux peak
    /// — see SpectralFlux for why this differs slightly from the Python.
    var threshFloor: Float = 0.04
    /// Two hits can't be closer than this.
    var minGapSeconds: Double = 0.040

    // MARK: Fingerprint
    /// ~93ms at 44.1k — long enough to resolve the inharmonic partials.
    var fpWindow: Int = 4096
    /// Skip the mallet click, keep the tone.
    var fpDelaySeconds: Double = 0.012
    var fpLoHz: Double = 200
    var fpHiHz: Double = 8000
    var fpBands: Int = 120
    /// Magnitude ** this. Tames loud/soft variation.
    var fpCompress: Float = 0.5
    /// Subtract this * pre-onset spectrum. Compression boosts quiet bands, which
    /// on real recordings means it boosts the noise floor — a broadband component
    /// every key shares. Measured on real gangsa: worst-pair similarity 0.583
    /// without subtraction, 0.417 with this at 3.0 over a 200-8000Hz band.
    var fpNoiseSub: Float = 3.0
    /// Guard between the noise window and the attack.
    var fpNoiseLeadSeconds: Double = 0.010

    // MARK: Matching
    /// The best template must beat the runner-up by this, else "unclear".
    /// Saying nothing beats telling a student they played a wrong note when they
    /// didn't. Real templates clear their nearest rival by 0.58-0.64.
    var confidenceGap: Float = 0.02

    /// Peak amplitude (abs sample, 0...~1) a capture must reach to count as a real
    /// strike. Below this it is a missed/too-soft hit or room noise — measured
    /// noise captures land near 0.002 while real strikes are 0.3+. Averaging a
    /// noise capture into a key template destroys it, so reject instead.
    var minStrikeAmplitude: Float = 0.03

    // MARK: Derived

    var minGapFrames: Int { Int(minGapSeconds * sampleRate / Double(onsetHop)) }

    /// Odd, so the median window has a true centre.
    var medianLengthFrames: Int {
        max(3, Int(medianLengthSeconds * sampleRate / Double(onsetHop)) | 1)
    }

    var fpDelaySamples: Int { Int(fpDelaySeconds * sampleRate) }
    var fpNoiseLeadSamples: Int { Int(fpNoiseLeadSeconds * sampleRate) }

    /// How much audio must exist after an onset before it can be fingerprinted.
    /// Onsets fire almost immediately but the fingerprint needs the note to have
    /// sounded — don't fight this with a shorter window, it is why strikes are
    /// reported ~100ms after they happen.
    var fingerprintLatencySamples: Int { fpDelaySamples + fpWindow }
}

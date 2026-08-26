//
//  DSPConfig.swift
//  Kotek
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

    // MARK: Amplitude gate
    //
    // Flux thresholds cannot separate mallet strikes from room noise and
    // handling — swept thresh_mult 1.6-5.0 x thresh_floor 0.04-0.30 in Python
    // and the spurious onsets stay flux-comparable. Amplitude does separate
    // them: measured 10-40x between real strikes and false positives.
    //
    // This matters more here than offline. Python normalises flux by the whole
    // clip's maximum — a real strike — so early room noise scores far below the
    // floor. A live stream has no such future: until the first loud strike the
    // running peak IS the noise, so noise divides by itself and reads as 1.0.
    // Measured on a real recording, that produced 7 phantom onsets in the first
    // second and none afterwards.
    //
    /// Absolute floor on the post-attack peak. Meaningful as an absolute number
    /// because samples are already scaled to full-scale = 1.0. Confirmed on
    /// device: noise captures land near 0.002 where real strikes are 0.3+, and
    /// averaging a noise capture into a key template wrecks it (an amp-0.002
    /// "strike" scored 0.36 self-similarity against a real hit).
    var minStrikeAmplitude: Float = 0.04
    /// And relative to recent strikes, so a quiet passage after a loud one does
    /// not flood with false positives.
    var minAmplitudeRelative: Float = 0.12
    /// Window used to measure that peak.
    var amplitudeMeasureSeconds: Double = 0.060

    // MARK: Fingerprint
    /// ~93ms at 44.1k — long enough to resolve the inharmonic partials.
    var fpWindow: Int = 4096
    /// Skip the mallet click, keep the tone.
    var fpDelaySeconds: Double = 0.012
    // 300-10000, chosen against real PLAYING rather than the calibration clips.
    // On a 9-note pattern 200-8000 scored 8/9 and 300-10000 scored 9/9, with the
    // neighbouring band (350-10000) agreeing, so it sits on a plateau rather
    // than a lucky spike. Must match --lo/--hi in build_calibration.py.
    var fpLoHz: Double = 300
    var fpHiHz: Double = 10000
    var fpBands: Int = 120
    /// Magnitude ** this. Tames loud/soft variation, at the cost of key
    /// separation — measured on real gangsa, worst-pair similarity was 0.575 at
    /// 0.5 (failing the <0.5 bar), 0.340 at 0.7, 0.183 at 1.0. Kept below 1.0
    /// because compression is what absorbs the extra brightness of a hard
    /// strike, and the reference recordings are all at one dynamic.
    /// Must match `--compress` in build_calibration.py.
    var fpCompress: Float = 0.7
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
    /// didn't. Raised from 0.02 after a real miss: a deng heard as dang won by
    /// only 0.083, where every correct call in the same pattern won by 0.25+.
    var confidenceGap: Float = 0.10

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

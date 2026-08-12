//
//  SpectralFlux.swift
//  gomelan
//
//  Port of `spectral_flux` in gamelan_dsp.py, one frame at a time.
//
//  Only *increases* in energy count. A struck key jumps quiet -> loud (positive).
//  A key still ringing is loud but FADING (negative), so it contributes nothing.
//  Without that clamp every sustained note would keep re-triggering as a new
//  strike. This is the whole trick.
//

import Accelerate

final class SpectralFlux {

    private let config: DSPConfig
    private let fft: FFTProcessor
    private let firstBin: Int

    private var spectrum: [Float] = []
    private var logSpectrum: [Float]
    private var previousLog: [Float]
    private var hasPrevious = false

    /// Python divides flux by the whole clip's maximum, which needs a future that
    /// a live stream does not have. Instead we track a decaying running peak and
    /// scale by that. The median-based part of the threshold is scale-invariant
    /// and unaffected; only `threshFloor` depends on this, and it behaves the
    /// same once a few strikes have been heard.
    private(set) var runningPeak: Float = 0
    private let peakDecay: Float = 0.9995

    /// Frames to observe before reporting anything.
    ///
    /// Without this the very first frame after a reset sets `runningPeak` to its
    /// own value, so `normalised` returns exactly 1.0 — the largest value
    /// possible — out of silence, and the detector fires immediately. The
    /// warm-up both suppresses that and lets the peak settle to something that
    /// reflects the room rather than one arbitrary frame.
    private var warmupRemaining = 0
    private var warmupFrames: Int

    var isWarmedUp: Bool { warmupRemaining <= 0 }

    init(config: DSPConfig, fft: FFTProcessor) {
        self.config = config
        self.fft = fft
        // Drop rumble below fluxFloorHz: handling noise, table thumps, air
        // conditioning. Never a gangsa partial, and a rich source of false onsets.
        self.firstBin = max(0, Int(ceil(config.fluxFloorHz * Double(fft.size) / config.sampleRate)))
        self.logSpectrum = [Float](repeating: 0, count: fft.binCount)
        self.previousLog = [Float](repeating: 0, count: fft.binCount)
        // ~250ms of room before anything counts.
        self.warmupFrames = max(8, Int(0.25 * config.sampleRate / Double(config.onsetHop)))
        self.warmupRemaining = warmupFrames
    }

    func reset() {
        hasPrevious = false
        runningPeak = 0
        warmupRemaining = warmupFrames
        for i in previousLog.indices { previousLog[i] = 0 }
    }

    /// Feed one window of `onsetWindow` samples. Returns raw (unnormalised) flux.
    func process(window samples: [Float]) -> Float {
        fft.magnitudeSpectrum(samples, into: &spectrum)

        // log1p(S * 20) — compress so soft hits still register. Without it a hard
        // strike produces an enormous jump and a gentle one a barely visible blip,
        // so no single threshold could catch both.
        //
        // Written through an explicit pointer because passing the same array as
        // both source and `inout` destination is an exclusivity violation that
        // traps at runtime.
        var scale: Float = 20
        var count = Int32(spectrum.count)
        let n = vDSP_Length(spectrum.count)
        spectrum.withUnsafeBufferPointer { src in
            logSpectrum.withUnsafeMutableBufferPointer { dst in
                vDSP_vsmul(src.baseAddress!, 1, &scale, dst.baseAddress!, 1, n)
                vvlog1pf(dst.baseAddress!, dst.baseAddress!, &count)
            }
        }

        var flux: Float = 0
        if hasPrevious {
            for bin in firstBin..<logSpectrum.count {
                let diff = logSpectrum[bin] - previousLog[bin]
                if diff > 0 { flux += diff }
            }
        }

        swap(&previousLog, &logSpectrum)
        hasPrevious = true

        runningPeak = max(runningPeak * peakDecay, flux)
        if warmupRemaining > 0 { warmupRemaining -= 1 }
        return flux
    }

    /// Flux scaled into roughly 0...1, the range Python's thresholds assume.
    /// Returns 0 during warm-up so nothing can trigger off the bootstrap frame.
    func normalised(_ flux: Float) -> Float {
        guard isWarmedUp, runningPeak > 0 else { return 0 }
        return flux / runningPeak
    }
}

//
//  Fingerprinter.swift
//  gomelan
//
//  Port of `fingerprint` and `_log_band_matrix` in gamelan_dsp.py.
//
//  Turns one struck note into a 120-element vector describing its spectral
//  SHAPE. L2 normalisation is what makes a soft hit and a hard hit on the same
//  key look alike — we compare shape, not loudness.
//
//  Why this and not a pitch estimate: bronze bars are inharmonic. Partials sit
//  at roughly 1, 2.76, 5.42, 8.91x the fundamental, not integer multiples, so
//  "find the fundamental" is both unreliable and throws away the very structure
//  that distinguishes one key from another. Measured on real gangsa, the worst
//  pair of these vectors scores 0.417 similarity, with every key clearing its
//  nearest rival by 0.58 or more.
//

import Accelerate

final class Fingerprinter {

    private let config: DSPConfig
    private let fft: FFTProcessor

    /// For each band, the FFT bins that fall inside it.
    private let bands: [[Int]]

    private var segment: [Float]
    private var noiseSegment: [Float]
    private var magnitude: [Float] = []
    private var noiseMagnitude: [Float] = []

    var vectorLength: Int { config.fpBands }

    init(config: DSPConfig, fft: FFTProcessor) {
        self.config = config
        self.fft = fft
        self.segment = [Float](repeating: 0, count: config.fpWindow)
        self.noiseSegment = [Float](repeating: 0, count: config.fpWindow)
        self.bands = Fingerprinter.buildBands(config: config, fft: fft)
    }

    /// Log-spaced band edges, ~66 cents each. Bands are defined in HERTZ, not in
    /// bin indices — that is what lets a 48kHz device match templates captured at
    /// 44.1kHz, provided this table is rebuilt at the runtime rate rather than
    /// copied from the calibration file.
    private static func buildBands(config: DSPConfig, fft: FFTProcessor) -> [[Int]] {
        let n = config.fpBands
        var edges = [Double](repeating: 0, count: n + 1)
        let ratio = log(config.fpHiHz / config.fpLoHz) / Double(n)
        for i in 0...n { edges[i] = config.fpLoHz * exp(ratio * Double(i)) }

        var result: [[Int]] = []
        result.reserveCapacity(n)
        for b in 0..<n {
            var bins: [Int] = []
            for bin in 0..<fft.binCount {
                let hz = fft.frequency(ofBin: bin, sampleRate: config.sampleRate)
                if hz >= edges[b] && hz < edges[b + 1] { bins.append(bin) }
            }
            if bins.isEmpty {
                // Band narrower than one FFT bin — take the nearest. At 200Hz a
                // 66-cent band is ~7.7Hz wide against ~10.8Hz bins, so the lowest
                // bands genuinely hit this case.
                let centre = (edges[b] + edges[b + 1]) / 2
                var nearest = 0
                var bestDistance = Double.greatestFiniteMagnitude
                for bin in 0..<fft.binCount {
                    let d = abs(fft.frequency(ofBin: bin, sampleRate: config.sampleRate) - centre)
                    if d < bestDistance { bestDistance = d; nearest = bin }
                }
                bins = [nearest]
            }
            result.append(bins)
        }
        return result
    }

    /// Fingerprint the note attacking at `onsetSample`.
    /// Returns nil when the required audio is not available, or the window held
    /// no energy.
    func fingerprint(onsetSample: Int, ring: SampleRing) -> [Float]? {
        let start = onsetSample + config.fpDelaySamples
        guard ring.read(from: start, count: config.fpWindow, into: &segment) else { return nil }

        fft.magnitudeSpectrum(segment, into: &magnitude)

        // Estimate the room/mic noise from the audio immediately BEFORE the
        // attack and take it out. Must happen on raw bins, before compression —
        // once the floor is compressed it has already contaminated the shape.
        if config.fpNoiseSub > 0 {
            let noiseEnd = onsetSample - config.fpNoiseLeadSamples
            let noiseStart = noiseEnd - config.fpWindow
            if noiseStart >= 0,
               ring.read(from: noiseStart, count: config.fpWindow, into: &noiseSegment) {
                fft.magnitudeSpectrum(noiseSegment, into: &noiseMagnitude)
                for i in magnitude.indices {
                    magnitude[i] = max(magnitude[i] - config.fpNoiseSub * noiseMagnitude[i], 0)
                }
            }
        }

        var vector = [Float](repeating: 0, count: config.fpBands)
        for (b, bins) in bands.enumerated() {
            var sum: Float = 0
            for bin in bins { sum += magnitude[bin] }
            vector[b] = sum
        }

        // Magnitude ** compress, then L2 normalise. In-place vDSP calls go
        // through an explicit pointer — passing the same array as source and
        // `inout` destination is an exclusivity violation that traps at runtime.
        var exponent = config.fpCompress
        var count = Int32(vector.count)
        let n = vDSP_Length(vector.count)
        vector.withUnsafeMutableBufferPointer { buffer in
            vvpowsf(buffer.baseAddress!, &exponent, buffer.baseAddress!, &count)
        }

        var norm: Float = 0
        vDSP_svesq(vector, 1, &norm, n)
        norm = sqrt(norm)
        guard norm > 1e-9 else { return nil }
        var inverse = 1 / norm
        vector.withUnsafeMutableBufferPointer { buffer in
            vDSP_vsmul(buffer.baseAddress!, 1, &inverse, buffer.baseAddress!, 1, n)
        }

        return vector
    }

    /// Strongest partials in the fingerprint window, as (hz, relative strength).
    /// For display and calibration feedback only — never for matching.
    func topPeaks(onsetSample: Int, ring: SampleRing, count wanted: Int = 4) -> [(hz: Double, strength: Double)] {
        let start = onsetSample + config.fpDelaySamples
        guard ring.read(from: start, count: config.fpWindow, into: &segment) else { return [] }
        fft.magnitudeSpectrum(segment, into: &magnitude)

        let loBin = max(1, Int(config.fpLoHz * Double(fft.size) / config.sampleRate))
        let hiBin = min(magnitude.count - 2, Int(config.fpHiHz * Double(fft.size) / config.sampleRate))
        guard loBin < hiBin else { return [] }

        var peaks: [(Int, Float)] = []
        for bin in loBin...hiBin where magnitude[bin] >= magnitude[bin - 1]
                                    && magnitude[bin] >= magnitude[bin + 1] {
            peaks.append((bin, magnitude[bin]))
        }
        guard let strongest = peaks.map({ $0.1 }).max(), strongest > 0 else { return [] }

        return peaks.sorted { $0.1 > $1.1 }.prefix(wanted).map {
            (hz: fft.frequency(ofBin: $0.0, sampleRate: config.sampleRate),
             strength: Double($0.1 / strongest))
        }
    }
}

//
//  FFTProcessor.swift
//  gomelan
//
//  vDSP real FFT producing magnitudes that match numpy's
//  `np.abs(np.fft.rfft(seg * np.hanning(N)))` bin for bin, so Swift results can
//  be diffed against the Python reference implementation.
//
//  Three details make that equivalence hold, and all three are easy to get wrong:
//
//  1. rfft returns N/2 + 1 bins, not N/2. The extra one is Nyquist.
//  2. vDSP_fft_zrip packs DC in realp[0] and Nyquist in imagp[0], so those two
//     must be unpacked by hand rather than treated as an ordinary complex pair.
//  3. vDSP_fft_zrip returns results scaled by 2. Undo it.
//
//  L2-normalised fingerprints would survive a wrong global scale, but flux
//  thresholds would not — and neither would any comparison against Python.
//

import Accelerate

final class FFTProcessor {

    let size: Int
    /// Number of magnitude bins produced: `size/2 + 1`, matching numpy rfft.
    let binCount: Int

    private let halfSize: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]

    // Scratch, reused across calls so the audio thread never allocates.
    private var windowed: [Float]
    private var real: [Float]
    private var imag: [Float]

    init(size: Int) {
        precondition(size > 0 && (size & (size - 1)) == 0, "FFT size must be a power of two")
        self.size = size
        self.halfSize = size / 2
        self.binCount = size / 2 + 1
        self.log2n = vDSP_Length(log2(Float(size)))
        self.setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

        // Built by hand rather than vDSP_hann_window: numpy's np.hanning is the
        // SYMMETRIC window (endpoints exactly zero, denominator N-1). vDSP's
        // variants differ in normalisation and periodicity, and a mismatch here
        // is invisible until fingerprints quietly stop agreeing with Python.
        self.window = [Float](repeating: 0, count: size)
        let denom = Float(size - 1)
        for i in 0..<size {
            window[i] = 0.5 - 0.5 * cos(2 * .pi * Float(i) / denom)
        }

        self.windowed = [Float](repeating: 0, count: size)
        self.real = [Float](repeating: 0, count: halfSize)
        self.imag = [Float](repeating: 0, count: halfSize)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Magnitude spectrum of `samples` (must hold at least `size` elements).
    /// Writes `binCount` values into `out`, which is resized if needed.
    func magnitudeSpectrum(_ samples: [Float], into out: inout [Float]) {
        precondition(samples.count >= size, "need at least \(size) samples")
        if out.count != binCount { out = [Float](repeating: 0, count: binCount) }

        samples.withUnsafeBufferPointer { src in
            vDSP_vmul(src.baseAddress!, 1, window, 1, &windowed, 1, vDSP_Length(size))
        }

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!,
                                            imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { wPtr in
                    wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self,
                                                        capacity: halfSize) { cPtr in
                        vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(halfSize))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                // DC and Nyquist are packed together in element 0.
                let dc = abs(realPtr[0]) * 0.5
                let nyquist = abs(imagPtr[0]) * 0.5

                out.withUnsafeMutableBufferPointer { dst in
                    dst[0] = dc
                    dst[halfSize] = nyquist
                    for bin in 1..<halfSize {
                        let re = realPtr[bin]
                        let im = imagPtr[bin]
                        dst[bin] = sqrt(re * re + im * im) * 0.5
                    }
                }
            }
        }
    }

    func magnitudeSpectrum(_ samples: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: binCount)
        magnitudeSpectrum(samples, into: &out)
        return out
    }

    /// Centre frequency of a bin. Matches np.fft.rfftfreq(size, 1/sampleRate).
    func frequency(ofBin bin: Int, sampleRate: Double) -> Double {
        Double(bin) * sampleRate / Double(size)
    }

    func bin(forFrequency hz: Double, sampleRate: Double) -> Int {
        Int((hz * Double(size) / sampleRate).rounded())
    }
}

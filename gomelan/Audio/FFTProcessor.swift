//
//  FFTProcessor.swift
//  gomelan
//
//  Thin vDSP wrapper producing a magnitude spectrum from a block of samples,
//  with a Hann window applied. Used by both the onset detector and the key
//  classifier (PRD §6.3).
//

import Accelerate

final class FFTProcessor {
    let size: Int
    private let halfSize: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]

    init(size: Int) {
        precondition(size > 0 && (size & (size - 1)) == 0, "FFT size must be a power of two")
        self.size = size
        self.halfSize = size / 2
        self.log2n = vDSP_Length(log2(Float(size)))
        self.setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Returns the magnitude spectrum (length `size/2`) for the given samples.
    /// `samples` must have at least `size` elements; extra elements are ignored.
    func magnitudeSpectrum(_ samples: [Float]) -> [Float] {
        var windowed = [Float](repeating: 0, count: size)
        samples.withUnsafeBufferPointer { src in
            vDSP_vmul(src.baseAddress!, 1, window, 1, &windowed, 1, vDSP_Length(size))
        }

        var real = [Float](repeating: 0, count: halfSize)
        var imag = [Float](repeating: 0, count: halfSize)
        var magnitudes = [Float](repeating: 0, count: halfSize)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { wPtr in
                    wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { cPtr in
                        vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(halfSize))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }

        // vDSP_zvmags gives squared magnitude; take the root for true magnitude.
        var count = Int32(halfSize)
        vvsqrtf(&magnitudes, magnitudes, &count)
        return magnitudes
    }

    /// Frequency (Hz) of a given bin index for a sample rate.
    func frequency(ofBin bin: Int, sampleRate: Double) -> Double {
        Double(bin) * sampleRate / Double(size)
    }

    /// Bin index nearest a given frequency.
    func bin(forFrequency hz: Double, sampleRate: Double) -> Int {
        Int((hz * Double(size) / sampleRate).rounded())
    }
}

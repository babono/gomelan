//
//  PCMWav.swift
//  Kotek
//
//  Float samples in, a WAV in memory out.
//
//  `AVAudioPlayer(data:)` wants a container it recognises, not bare samples. So
//  anything that BUILDS a signal here rather than shipping it as a file — the
//  octave-folded splash stroke, the shortened kajar tick under every tap — has
//  to hand it back through a container before it can be played.
//
//  This was `SplashChime`'s private encoder until the tick needed the same
//  thing. It is deliberately the minimum RIFF a player will accept: mono 16-bit
//  PCM, no metadata, no chunks beyond `fmt ` and `data`.
//
//  `nonisolated` so a signal can be built off the main thread; it holds no
//  state, so there is nothing for that to race against.
//

import Foundation

nonisolated enum PCMWav {

    /// Mono 16-bit PCM in a minimal RIFF container. Samples outside -1…1 are
    /// clamped rather than wrapped — a wrap is a full-scale discontinuity, and
    /// on a struck sound that reads as a crack rather than as loudness.
    static func encode(_ samples: [Float], sampleRate: Int) -> Data {
        let bytesPerSample = 2
        let dataBytes = samples.count * bytesPerSample
        var data = Data(capacity: 44 + dataBytes)

        func append(_ string: String) { data.append(contentsOf: string.utf8) }
        func append32(_ value: Int) {
            var v = UInt32(truncatingIfNeeded: value).littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func append16(_ value: Int) {
            var v = UInt16(truncatingIfNeeded: value).littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }

        append("RIFF")
        append32(36 + dataBytes)
        append("WAVE")
        append("fmt ")
        append32(16)                                   // PCM header size
        append16(1)                                    // PCM, uncompressed
        append16(1)                                    // mono
        append32(sampleRate)
        append32(sampleRate * bytesPerSample)          // byte rate
        append16(bytesPerSample)                       // block align
        append16(16)                                   // bits per sample
        append("data")
        append32(dataBytes)

        for sample in samples {
            let clamped = max(-1, min(1, sample))
            append16(Int(clamped * 32767))
        }
        return data
    }
}

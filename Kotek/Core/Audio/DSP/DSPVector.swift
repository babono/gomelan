//
//  DSPVector.swift
//  Kotek
//
//  Vector math helpers powered by Accelerate vDSP.
//

import Accelerate

enum DSPVector {
    /// Computes the dot product of two single-precision float vectors using
    /// Accelerate vDSP SIMD instructions.
    @inline(__always)
    static func dot(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var sum: Float = 0
        vDSP_dotpr(a, 1, b, 1, &sum, vDSP_Length(a.count))
        return sum
    }
}

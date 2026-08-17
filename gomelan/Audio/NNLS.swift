//
//  NNLS.swift
//  gomelan
//
//  Non-negative least squares:  min ||y - Dᵀx||²  subject to  x >= 0.
//
//  Why this exists. Every other matcher in this app is 1-of-N: KeyClassifier
//  picks the single template with the best cosine and refuses when the top two
//  are too close. That is the right shape for "was this a gangsa strike at all",
//  and the wrong shape for a ringing instrument. Bronze sustains for seconds. By
//  the third note of a kotekan the microphone is hearing three keys at once, and
//  asking "which ONE key is this" has no true answer — so the classifier either
//  names the loudest still-ringing key or declines.
//
//  NNLS asks the answerable question instead: what non-negative mixture of the
//  known keys explains what I am hearing? Overlap stops being noise to reject
//  and becomes the thing being measured.
//
//  Solved by multiplicative updates, which keep x >= 0 by construction — no
//  active-set bookkeeping, no projection step. Lawson-Hanson is exact but much
//  longer, and at 10-12 atoms the difference does not survive the microphone.
//
//  On the Gram trick. The naive update reconstructs the full spectrum each
//  iteration: O(atoms x bands) with a bands-long temporary allocated inside the
//  loop. Precomputing G = D·Dᵀ once makes the update O(atoms²) with no
//  allocation at all — 12x12 = 144 multiply-adds per iteration against 12x120 =
//  1440, and nothing touching the heap. This runs on the audio DSP queue for
//  every strike, so that matters.
//
//    x <- x * (D·y) / (G·x)
//

import Accelerate

/// A dictionary of non-negative atoms, prepared once and solved against many
/// observations. Holding the Gram matrix is the whole point of the type — build
/// it per profile, not per strike.
struct NNLSDictionary {

    /// One row per atom, each `bandCount` long. Rows are L2-normalised by the
    /// builder so that a loud key cannot outbid a quiet one on scale alone.
    private let atoms: [[Float]]
    /// G[i][j] = <atom_i, atom_j>, flattened row-major.
    private let gram: [Float]

    let atomCount: Int
    let bandCount: Int

    /// Atoms must already be L2-normalised — see `KeyDecomposer` for the
    /// builder that does it. Passing raw energies here silently biases the fit.
    init(normalisedAtoms: [[Float]]) {
        self.atoms = normalisedAtoms
        self.atomCount = normalisedAtoms.count
        self.bandCount = normalisedAtoms.first?.count ?? 0

        var g = [Float](repeating: 0, count: atomCount * atomCount)
        let n = vDSP_Length(bandCount)
        for i in 0..<atomCount {
            for j in i..<atomCount {
                var dot: Float = 0
                vDSP_dotpr(normalisedAtoms[i], 1, normalisedAtoms[j], 1, &dot, n)
                g[i * atomCount + j] = dot
                g[j * atomCount + i] = dot
            }
        }
        self.gram = g
    }

    /// Activation of each atom in `observation`, in the observation's own units.
    ///
    /// `observation` is the raw band vector — deliberately NOT normalised, so the
    /// activations carry loudness and a soft strike reads as a soft strike.
    ///
    /// 30 iterations was enough for the residual to stop moving in the third
    /// decimal on real captures; there is no benefit to more and the cost is
    /// linear in it.
    func solve(observation y: [Float], iterations: Int = 30) -> [Float] {
        guard atomCount > 0, y.count == bandCount else {
            return [Float](repeating: 0, count: atomCount)
        }
        let eps: Float = 1e-9
        let n = vDSP_Length(bandCount)

        // dy[a] = <atom_a, y>. The whole band-length side of the problem is done
        // here, once, and never touched again inside the loop.
        var dy = [Float](repeating: 0, count: atomCount)
        for a in 0..<atomCount {
            vDSP_dotpr(atoms[a], 1, y, 1, &dy[a], n)
        }

        // Seeding at the correlation rather than at 1 starts the fit near the
        // answer, which matters because multiplicative updates cannot resurrect
        // an atom once it reaches zero: a bad start is permanent.
        var x = dy.map { max($0, eps) }
        var gx = [Float](repeating: 0, count: atomCount)
        let m = vDSP_Length(atomCount)

        for _ in 0..<iterations {
            gram.withUnsafeBufferPointer { gPtr in
                x.withUnsafeBufferPointer { xPtr in
                    gx.withUnsafeMutableBufferPointer { out in
                        vDSP_mmul(gPtr.baseAddress!, 1, xPtr.baseAddress!, 1,
                                  out.baseAddress!, 1, m, 1, m)
                    }
                }
            }
            for a in 0..<atomCount {
                let updated = x[a] * dy[a] / (gx[a] + eps)
                x[a] = (updated.isFinite && updated > 0) ? updated : 0
            }
        }
        return x
    }

    /// Fraction of the observation's energy the fit failed to explain, 0...1.
    ///
    /// The number that says "none of these atoms is what I am hearing" — a
    /// neighbouring instrument, a voice, a dropped mallet. A confident-looking
    /// activation on top of a large residual is not confidence, it is the least
    /// bad way of describing something the dictionary has never seen.
    func residualFraction(observation y: [Float], activations x: [Float]) -> Float {
        guard x.count == atomCount, y.count == bandCount else { return 1 }
        var recon = [Float](repeating: 0, count: bandCount)
        let n = vDSP_Length(bandCount)
        for a in 0..<atomCount where x[a] > 0 {
            var scale = x[a]
            recon.withUnsafeMutableBufferPointer { dst in
                vDSP_vsma(atoms[a], 1, &scale, dst.baseAddress!, 1, dst.baseAddress!, 1, n)
            }
        }
        var diff = [Float](repeating: 0, count: bandCount)
        vDSP_vsub(recon, 1, y, 1, &diff, 1, n)

        var residual: Float = 0
        var total: Float = 0
        vDSP_svesq(diff, 1, &residual, n)
        vDSP_svesq(y, 1, &total, n)
        guard total > 1e-12 else { return 1 }
        return min(1, sqrt(residual / total))
    }
}

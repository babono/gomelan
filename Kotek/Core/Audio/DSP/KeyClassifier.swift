//
//  KeyClassifier.swift
//  Kotek
//
//  Port of `Calibration.match` in gamelan_dsp.py.
//
//  Cosine similarity against the stored per-key fingerprints — which, because
//  both sides are L2-normalised, is just a dot product. Ten keys x 120 floats is
//  trivial work; this is not where any time goes.
//
//  Replaces the earlier fundamental-frequency-in-cents matcher. That approach
//  assumes a harmonic series to find a fundamental with, and gamelan bronze is
//  inharmonic — see Fingerprinter for the partial ratios. It also assumed key
//  pitches are known in advance, but every gamelan is tuned differently, so the
//  only reliable reference is the instrument in front of the user.
//

import Accelerate

struct KeyMatch {
    let keyIndex: Int
    /// Cosine similarity of the winning template, 0...1.
    let similarity: Double
    /// How far the winner beat the runner-up. This is the number that decides
    /// whether the match is trustworthy.
    let gap: Double
    /// Estimated fundamental, for display only. Never used for matching.
    var fundamentalHz: Double = 0

    /// Kept for call sites that show a 0...1 confidence. Derived from the margin
    /// over the runner-up, since a high similarity means nothing on its own if
    /// two keys score equally.
    var confidence: Double { min(1, max(0, gap / 0.3)) }
}

final class KeyClassifier {

    private var config: DSPConfig
    private var indices: [Int] = []
    private var templates: [[Float]] = []

    init(config: DSPConfig, keys: [InstrumentKey]) {
        self.config = config
        updateKeys(keys)
    }

    /// Keys without a stored fingerprint are skipped — they cannot be matched
    /// and must be re-run through calibration.
    func updateKeys(_ keys: [InstrumentKey]) {
        indices.removeAll(keepingCapacity: true)
        templates.removeAll(keepingCapacity: true)
        for key in keys {
            guard let vector = key.fingerprint, vector.count == config.fpBands else { continue }
            indices.append(key.index)
            templates.append(vector)
        }
    }

    var calibratedKeyCount: Int { templates.count }

    /// Every template's score, best first. For diagnostics and calibration UI.
    func scores(for vector: [Float]) -> [(keyIndex: Int, similarity: Double)] {
        zip(indices, templates)
            .map { (keyIndex: $0.0, similarity: Double(dot($0.1, vector))) }
            .sorted { $0.similarity > $1.similarity }
    }

    /// Returns nil when the top two templates are too close to call.
    /// This "unclear" state is deliberate: telling a student they played a wrong
    /// note when they didn't is worse than saying nothing.
    func classify(vector: [Float]) -> KeyMatch? {
        guard !templates.isEmpty else { return nil }

        var bestIndex = -1
        var best: Float = -.greatestFiniteMagnitude
        var second: Float = -.greatestFiniteMagnitude

        for (i, template) in templates.enumerated() {
            let score = dot(template, vector)
            if score > best {
                second = best
                best = score
                bestIndex = i
            } else if score > second {
                second = score
            }
        }
        guard bestIndex >= 0 else { return nil }

        // A single calibrated key has no runner-up to be confused with.
        let gap = templates.count == 1 ? 1 : best - second
        guard gap >= config.confidenceGap else { return nil }

        return KeyMatch(keyIndex: indices[bestIndex],
                        similarity: Double(best),
                        gap: Double(gap))
    }

    private func dot(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }

    // MARK: - Calibration support

    /// Average several fingerprints of the same key into one template.
    ///
    /// Averaging across dynamics is the single biggest accuracy win available —
    /// hard strikes are brighter than soft ones, and one template per key
    /// captures only whichever dynamic happened to be used on the day.
    static func averageFingerprints(_ vectors: [[Float]]) -> [Float]? {
        guard let first = vectors.first, !first.isEmpty else { return nil }
        var sum = [Float](repeating: 0, count: first.count)
        let n = vDSP_Length(sum.count)
        for vector in vectors where vector.count == first.count {
            sum.withUnsafeMutableBufferPointer { dst in
                vDSP_vadd(dst.baseAddress!, 1, vector, 1, dst.baseAddress!, 1, n)
            }
        }
        var norm: Float = 0
        vDSP_svesq(sum, 1, &norm, n)
        norm = sqrt(norm)
        guard norm > 1e-9 else { return nil }
        var inverse = 1 / norm
        sum.withUnsafeMutableBufferPointer { dst in
            vDSP_vsmul(dst.baseAddress!, 1, &inverse, dst.baseAddress!, 1, n)
        }
        return sum
    }

    /// Worst-case similarity between any two calibrated keys.
    ///
    /// With few hits per key this is the only accuracy figure available — a real
    /// leave-one-out test needs repeats. Want < 0.5; the pair reported here is
    /// the one most likely to be confused during play.
    func separability() -> (worst: Double, mean: Double, pair: (Int, Int))? {
        guard templates.count >= 2 else { return nil }
        var worst = -Double.greatestFiniteMagnitude
        var total = 0.0
        var count = 0
        var pair = (0, 0)
        for i in 0..<templates.count {
            for j in (i + 1)..<templates.count {
                let score = Double(dot(templates[i], templates[j]))
                total += score
                count += 1
                if score > worst { worst = score; pair = (indices[i], indices[j]) }
            }
        }
        return (worst, total / Double(count), pair)
    }
}

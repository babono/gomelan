//
//  ProjectionAligner.swift
//  Kotek
//
//  A model-free bilah locator tuned to this instrument's structure. Viewed
//  top-down, the bronze bars are bright vertical columns separated by the dark
//  rope/gap/trough between them. Summing luminance down each column gives a 1-D
//  profile with one bright hump per bar; the humps' x-extents are the bars, and
//  a shared vertical band (from the row profile over those columns) gives their
//  height. No training, and it exploits exactly the layout the generic rectangle
//  detector and the tiny object-detector both struggle with.
//
//  Returns rects normalised 0–1 in the BUFFER's space, top-left origin — the same
//  convention as KeyDetector — so the caller maps them through CropMapper like any
//  other detection. Returns [] when the scene is too flat/ambiguous to trust.
//

import CoreGraphics

enum ProjectionAligner {

    static func detect(in image: CGImage, count: Int) -> [NormalizedRect] {
        guard count > 0 else { return [] }
        let W = 256, H = 96

        // Downsample to a small grayscale buffer (bottom-left origin, per CGContext).
        var data = [UInt8](repeating: 0, count: W * H)
        guard let ctx = CGContext(data: &data, width: W, height: H,
                                  bitsPerComponent: 8, bytesPerRow: W,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: W, height: H))

        // Column profile over a central vertical band (avoids frame ends).
        let bandLo = H / 4, bandHi = 3 * H / 4
        var col = [Double](repeating: 0, count: W)
        for x in 0..<W {
            var s = 0.0
            for r in bandLo..<bandHi { s += Double(data[r * W + x]) }
            col[x] = s / Double(bandHi - bandLo)
        }
        col = smooth(col, window: max(3, W / (count * 6)))

        guard let (lo, hi) = minMax(col), hi - lo > 8 else { return [] } // too flat
        let threshold = lo + (hi - lo) * 0.45

        // Bright runs = candidate bars.
        var runs = brightRuns(col, threshold: threshold)
        let minWidth = max(2, W / (count * 8))
        runs = runs.filter { $0.1 - $0.0 + 1 >= minWidth }
        guard runs.count >= count else { return [] }

        // Keep the `count` widest, then order left-to-right.
        let chosen = runs.sorted { ($0.1 - $0.0) > ($1.1 - $1.0) }
                         .prefix(count)
                         .sorted { $0.0 < $1.0 }

        // Shared vertical band from the row profile over the chosen columns.
        var rowProf = [Double](repeating: 0, count: H)
        var colCount = 0
        for (a, b) in chosen { colCount += (b - a + 1) }
        if colCount > 0 {
            for r in 0..<H {
                var s = 0.0
                for (a, b) in chosen { for x in a...b { s += Double(data[r * W + x]) } }
                rowProf[r] = s / Double(colCount)
            }
        }
        rowProf = smooth(rowProf, window: 3)
        let band = widestBrightRun(rowProf) ?? (bandLo, bandHi - 1)

        // CGContext rows are bottom-up; convert the band to a top-left y/height.
        let yTop = 1.0 - Double(band.1 + 1) / Double(H)
        let hNorm = Double(band.1 - band.0 + 1) / Double(H)

        return chosen.map { a, b in
            let x = Double(a) / Double(W)
            let w = Double(b - a + 1) / Double(W)
            let padX = w * 0.1   // bars read a touch wider than their bright core
            return NormalizedRect(x: max(0, x - padX),
                                  y: max(0, yTop),
                                  w: min(1, w + 2 * padX),
                                  h: min(1, hNorm))
        }
    }

    // MARK: - Helpers

    private static func brightRuns(_ a: [Double], threshold: Double) -> [(Int, Int)] {
        var runs: [(Int, Int)] = []
        var start: Int?
        for x in a.indices {
            if a[x] >= threshold {
                if start == nil { start = x }
            } else if let s = start {
                runs.append((s, x - 1)); start = nil
            }
        }
        if let s = start { runs.append((s, a.count - 1)) }
        return runs
    }

    private static func widestBrightRun(_ a: [Double]) -> (Int, Int)? {
        guard let (lo, hi) = minMax(a) else { return nil }
        let threshold = lo + (hi - lo) * 0.4
        return brightRuns(a, threshold: threshold).max { ($0.1 - $0.0) < ($1.1 - $1.0) }
    }

    private static func smooth(_ a: [Double], window: Int) -> [Double] {
        guard window > 1, a.count > window else { return a }
        let half = window / 2
        var out = a
        for i in a.indices {
            var s = 0.0, n = 0
            for j in max(0, i - half)...min(a.count - 1, i + half) { s += a[j]; n += 1 }
            out[i] = s / Double(n)
        }
        return out
    }

    private static func minMax(_ a: [Double]) -> (Double, Double)? {
        guard let lo = a.min(), let hi = a.max() else { return nil }
        return (lo, hi)
    }
}

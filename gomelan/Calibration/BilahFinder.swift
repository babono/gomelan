//
//  BilahFinder.swift
//  gomelan
//
//  Predicts where the bilah are, inside the region the player framed them into.
//
//  Why not a detector? Because this problem hands us three constraints an
//  object detector throws away, and which together make the answer almost
//  overdetermined:
//
//   1. WE KNOW THE COUNT. The player told us in step 1/3.
//   2. WE KNOW THE REGION. They framed it in step 2/3, so the table, the floor
//      and the wooden frame ends are largely excluded.
//   3. WE KNOW THE ROW IS PERIODIC. Bilah are hung at an even pitch. So rather
//      than finding N bars independently and hoping, we fit ONE comb of N teeth
//      — pitch and phase — to the image. Two unknowns instead of 4N, which is
//      why this survives glare, shadow and a bar or two being obscured.
//
//  WHAT NOT TO KEY ON. Two appealing signals both fail across real instruments,
//  measured on actual frames rather than assumed:
//
//   · Brightness. Bronze is played over pale floors that are BRIGHTER than it,
//     and a bar in shadow (value 0.41 in one frame) is darker than sunlit wood.
//   · Colour. "Warm and saturated" describes the TEAK FRAME better than the
//     bars — the ends measured 0.93 saturation against bronze's 0.55, which is
//     enough to drag a mask onto the frame and shift the whole row by one. And
//     it collapses completely on the many gangsa whose bilah are painted BLACK:
//     dark, colourless bars on a pale ground, the exact inverse of bronze.
//
//  So the profile here is built on STRUCTURE, not appearance:
//
//   · BAND-PASS. The column profile has its local mean subtracted over ~1.5
//     pitches, which annihilates anything broad — the table, the gravel, the
//     wooden ends — and keeps only variation at the scale of a bar. What a bar
//     IS, is a step away from its surroundings at the row's own frequency.
//   · BOTH POLARITIES. The comb is fitted to the profile and to its negation,
//     and the better fit wins. Bright bars on a dark trough and dark bars on a
//     pale floor are then the same problem. Bars, not gaps, win the tie because
//     there are N bars and only N−1 gaps, so a comb of N teeth on the gaps has
//     to hang one tooth off the end.
//
//  Colour survives only as a SECOND CANDIDATE profile, tried alongside
//  luminance and kept if it fits better — a bonus on bronze, silent elsewhere.
//
//  Deterministic, tens of milliseconds, no model, no network. Returns rects
//  normalised 0–1 within the image it was given, or [] when the scene carries
//  no periodic structure to trust.
//

import CoreGraphics

enum BilahFinder {

    static func find(in image: CGImage, count: Int) -> [NormalizedRect] {
        guard count > 0 else { return [] }
        let W = 320, H = 120
        guard let maps = sample(image, width: W, height: H) else { return [] }

        let nominalPitch = Double(W) / Double(count)
        var best: (score: Double, comb: Comb, profile: [Double], map: [Double])?

        // Two ways of seeing the frame, two polarities each. Whichever carries
        // the clearest row of N evenly spaced things, wins.
        for map in [maps.luma, maps.gold] {
            let raw = columnProfile(map, width: W, height: H)
            let banded = bandPass(smooth(raw, window: 3), window: Int(nominalPitch * 1.5))
            for polarity in [1.0, -1.0] {
                let signed = normalise(banded.map { $0 * polarity })
                guard let comb = fitComb(to: signed, count: count, width: W) else { continue }
                if best == nil || comb.score > best!.score {
                    let oriented = polarity > 0 ? map : map.map { -$0 }
                    best = (comb.score, comb, signed, oriented)
                }
            }
        }

        guard let winner = best else { return [] }
        let profile = winner.profile

        // Grow each tooth out to the bar's own edges, bounded by half a pitch so
        // neighbours can never swallow each other.
        let limit = Int(winner.comb.pitch * 0.46)
        var spans: [(Int, Int)] = []
        for centre in winner.comb.centres {
            //R One rigid pitch cannot fit a row seen in perspective — the fit
            //R drifted a few pixels by the far end. Let each tooth settle on its
            //R own bar first, bounded well inside half a pitch so it can never
            //R walk onto its neighbour.
            let c = refine(centre, in: profile, within: winner.comb.pitch * 0.3)
            let floorLevel = max(0.30, profile[c] * 0.45)
            var a = c, b = c
            while a > 0, c - a < limit, profile[a - 1] >= floorLevel { a -= 1 }
            while b < W - 1, b - c < limit, profile[b + 1] >= floorLevel { b += 1 }
            spans.append((a, b))
        }
        guard spans.count == count else { return [] }

        let bands = verticalBands(spans, in: winner.map, width: W, height: H)

        return zip(spans, bands).map { span, band in
            // The bar reads a touch wider than its core — the edges fall into
            // shadow — so give each mask a little room.
            let x = Double(span.0) / Double(W)
            let w = Double(span.1 - span.0 + 1) / Double(W)
            let pad = w * 0.06
            return NormalizedRect(x: max(0, x - pad),
                                  y: band.y,
                                  w: min(1 - max(0, x - pad), w + 2 * pad),
                                  h: band.h)
        }
    }

    // MARK: - Sampling

    private struct Maps {
        let luma: [Double]
        let gold: [Double]
    }

    private static func sample(_ image: CGImage, width W: Int, height H: Int) -> Maps? {
        var pixels = [UInt8](repeating: 0, count: W * H * 4)
        guard let ctx = CGContext(data: &pixels, width: W, height: H,
                                  bitsPerComponent: 8, bytesPerRow: W * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        //R CGContext draws bottom-up; flip so row 0 is the top of the picture and
        //R the y we hand back needs no second inversion.
        ctx.translateBy(x: 0, y: CGFloat(H))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: W, height: H))

        var luma = [Double](repeating: 0, count: W * H)
        var gold = [Double](repeating: 0, count: W * H)
        for i in 0..<(W * H) {
            let r = Double(pixels[i * 4]) / 255
            let g = Double(pixels[i * 4 + 1]) / 255
            let b = Double(pixels[i * 4 + 2]) / 255
            luma[i] = 0.299 * r + 0.587 * g + 0.114 * b
            gold[i] = goldness(r: r, g: g, b: b)
        }
        return Maps(luma: luma, gold: gold)
    }

    /// How bronze a pixel is. Bronze is YELLOW where the teak frame it hangs
    /// from is red-brown: measured across frames, green sits ~0.60 of the way
    /// from blue to red on bronze (0.50 even in shadow) against ~0.44 on teak.
    /// Saturation rejects a pale floor, which is yellowish but colourless.
    ///
    /// Worth nothing at all on black-painted bilah — which is exactly why this
    /// is only ever a candidate profile, never the only one.
    private static func goldness(r: Double, g: Double, b: Double) -> Double {
        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        guard maxC > 0.06, r > b else { return 0 }
        let saturation = (maxC - minC) / maxC
        let yellow = (g - b) / max(0.02, r - b)

        return smoothstep(0.25, 0.45, saturation)
             * smoothstep(0.46, 0.58, yellow)
             * (0.4 + 0.6 * smoothstep(0.15, 0.50, maxC))
    }

    // MARK: - Profiles

    /// Averaged down the middle of the frame: the rope ties and the wooden rails
    /// cross the bars near the top and bottom edges of the region.
    private static func columnProfile(_ map: [Double], width W: Int, height H: Int) -> [Double] {
        let lo = H * 22 / 100, hi = H * 78 / 100
        var out = [Double](repeating: 0, count: W)
        for x in 0..<W {
            var s = 0.0
            for y in lo..<hi { s += map[y * W + x] }
            out[x] = s / Double(hi - lo)
        }
        return out
    }

    private static func rowProfile(_ map: [Double], over spans: [(Int, Int)],
                                   width W: Int, height H: Int) -> [Double] {
        var out = [Double](repeating: 0, count: H)
        var n = 0
        for (a, b) in spans where a <= b { n += (b - a + 1) }
        guard n > 0 else { return out }
        for y in 0..<H {
            var s = 0.0
            for (a, b) in spans where a <= b {
                for x in a...b { s += map[y * W + x] }
            }
            out[y] = s / Double(n)
        }
        return out
    }

    /// Subtract the local mean: kills everything broader than a bar — the table,
    /// the gravel, the wooden ends — and leaves only structure at the row's own
    /// scale. This is what makes the finder indifferent to what colour the bars
    /// are, and to what they are lying on.
    private static func bandPass(_ a: [Double], window: Int) -> [Double] {
        let w = max(3, window)
        let local = smooth(a, window: w)
        return zip(a, local).map { $0 - $1 }
    }

    private static func normalise(_ a: [Double]) -> [Double] {
        guard let lo = a.min(), let hi = a.max(), hi - lo > 1e-6 else {
            return [Double](repeating: 0, count: a.count)
        }
        return a.map { ($0 - lo) / (hi - lo) }
    }

    // MARK: - The comb

    private struct Comb {
        let pitch: Double
        let centres: [Double]
        let score: Double
    }

    /// Fit N evenly spaced teeth to the profile: the (pitch, phase) whose teeth
    /// sit on the most signal. Brute force over a sensible range — a few hundred
    /// thousand adds, which is nothing, and it cannot get stuck in a local
    /// maximum the way a greedy run-finder does.
    private static func fitComb(to profile: [Double], count: Int, width W: Int) -> Comb? {
        guard count > 1 else {
            guard let peak = profile.indices.max(by: { profile[$0] < profile[$1] }) else { return nil }
            return Comb(pitch: Double(W), centres: [Double(peak)], score: profile[peak])
        }

        let nominal = Double(W) / Double(count)
        var bestScore = -Double.infinity
        var best: Comb?

        var pitchSteps: [Double] = []
        var p = nominal * 0.72
        while p <= nominal * 1.25 { pitchSteps.append(p); p += nominal * 0.01 }

        for pitch in pitchSteps {
            let span = pitch * Double(count - 1)
            guard span < Double(W) else { continue }
            var start = 0.0
            while start + span <= Double(W - 1) {
                var score = 0.0
                for i in 0..<count {
                    let x = start + pitch * Double(i)
                    score += sample(profile, at: x)
                    // The gap either side of a bar is as much a part of the
                    // pattern as the bar itself, and it is what stops the comb
                    // settling on one wide smear.
                    score -= 0.5 * sample(profile, at: x - pitch * 0.5)
                    score -= 0.5 * sample(profile, at: x + pitch * 0.5)
                }
                if score > bestScore {
                    bestScore = score
                    best = Comb(pitch: pitch,
                                centres: (0..<count).map { start + pitch * Double($0) },
                                score: score / Double(count))
                }
                start += 0.5
            }
        }

        // A real row scores strongly positive; noise hovers near zero.
        guard let comb = best, comb.score > 0.12 else { return nil }
        return comb
    }

    /// Slide a tooth onto the strongest signal within `range`, judged over a
    /// small window so a single bright pixel cannot pull it.
    private static func refine(_ centre: Double, in profile: [Double], within range: Double) -> Int {
        let lo = Int((centre - range).rounded()), hi = Int((centre + range).rounded())
        guard lo < hi else { return min(max(Int(centre.rounded()), 0), profile.count - 1) }

        var best = min(max(Int(centre.rounded()), 0), profile.count - 1)
        var bestScore = -Double.infinity
        for x in max(0, lo)...min(profile.count - 1, hi) {
            var s = 0.0
            for d in -2...2 { s += sample(profile, at: Double(x + d)) }
            if s > bestScore { bestScore = s; best = x }
        }
        return best
    }

    private static func sample(_ a: [Double], at x: Double) -> Double {
        guard !a.isEmpty else { return 0 }
        let clamped = min(max(x, 0), Double(a.count - 1))
        let i = Int(clamped)
        let f = clamped - Double(i)
        let j = min(i + 1, a.count - 1)
        return a[i] * (1 - f) + a[j] * f
    }

    // MARK: - Vertical extent

    /// Each bilah's OWN top and bottom.
    ///
    /// One shared band was the obvious simplification and it is wrong in two
    /// ordinary situations: a row seen slightly off-square climbs or falls
    /// across the frame, and many figures graduate in length. So each bar's
    /// extent is measured from its own columns.
    ///
    /// Measured per bar, but not TRUSTED per bar. A single bar's own reading is
    /// noisy — the bamboo rails and rope ties cross each one at a different
    /// height, and a highlight or a mallet can eat an end — so taking each
    /// measurement at face value gives a raggedly uneven row.
    ///
    /// What varies for real, though, varies SMOOTHLY: a row photographed
    /// slightly off-square climbs or falls steadily across the frame, and a
    /// graduated set shortens steadily along it. So a straight line is fitted
    /// through the measured tops and another through the bottoms, outliers
    /// discarded and refitted, and every bar takes its extent from the fit. Real
    /// tilt and real graduation survive; per-bar noise does not.
    private static func verticalBands(_ spans: [(Int, Int)], in map: [Double],
                                      width W: Int, height H: Int) -> [(y: Double, h: Double)] {
        let own = spans.map { verticalBand(rowProfile(map, over: [$0], width: W, height: H), height: H) }
        guard own.count >= 4 else { return own }

        //R Fitting top and bottom independently let the two lines diverge, and a
        //R noisy end bar dragged them into a 2:1 taper no gangsa has. Centre and
        //R height are fitted separately instead, and the height is held within a
        //R little of the row's median: the tilt is real and worth following, a
        //R doubling in length is a measurement error.
        let centre = robustLine(own.map { $0.y + $0.h / 2 })
        let height = robustLine(own.map(\.h))
        let median = own.map(\.h).sorted()[own.count / 2]

        return own.indices.map { i in
            let h = min(max(height(Double(i)), median * 0.85), median * 1.15)
            let y = max(0, centre(Double(i)) - h / 2)
            return (y: y, h: min(1 - y, h))
        }
    }

    /// Least squares through (index, value), then one pass discarding points far
    /// from that line and refitting — so one badly-read bar cannot tilt the row.
    private static func robustLine(_ values: [Double]) -> (Double) -> Double {
        func fit(_ points: [(x: Double, y: Double)]) -> (slope: Double, intercept: Double) {
            let n = Double(points.count)
            guard n > 1 else { return (0, points.first?.y ?? 0) }
            let sumX = points.reduce(0) { $0 + $1.x }
            let sumY = points.reduce(0) { $0 + $1.y }
            let sumXY = points.reduce(0) { $0 + $1.x * $1.y }
            let sumXX = points.reduce(0) { $0 + $1.x * $1.x }
            let denominator = n * sumXX - sumX * sumX
            guard abs(denominator) > 1e-9 else { return (0, sumY / n) }
            let slope = (n * sumXY - sumX * sumY) / denominator
            return (slope, (sumY - slope * sumX) / n)
        }

        let points = values.enumerated().map { (x: Double($0.offset), y: $0.element) }
        var line = fit(points)

        let residuals = points.map { abs($0.y - (line.slope * $0.x + line.intercept)) }
        let spread = residuals.sorted()[residuals.count / 2]
        let tolerance = max(spread * 2.5, 0.015)
        let kept = points.filter { abs($0.y - (line.slope * $0.x + line.intercept)) <= tolerance }
        if kept.count >= max(3, points.count / 2) { line = fit(kept) }

        return { x in line.slope * x + line.intercept }
    }

    /// The top and bottom of whatever the given columns contain, as the widest
    /// run of the row profile above a low threshold. Kept low on purpose: a
    /// polished bar blows out to near-white at the ends and a painted one falls
    /// into shadow, so a strict threshold clips both.
    private static func verticalBand(_ rows: [Double], height H: Int) -> (y: Double, h: Double) {
        let smoothed = normalise(smooth(rows, window: 5))
        guard let lo = smoothed.min(), let hi = smoothed.max(), hi - lo > 0.02 else {
            return (0.16, 0.68)
        }
        let threshold = lo + (hi - lo) * 0.28

        var best: (Int, Int)?
        var start: Int?
        for y in smoothed.indices {
            if smoothed[y] >= threshold {
                if start == nil { start = y }
            } else if let s = start {
                if best == nil || (y - s) > (best!.1 - best!.0) { best = (s, y - 1) }
                start = nil
            }
        }
        if let s = start, best == nil || (smoothed.count - s) > (best!.1 - best!.0) {
            best = (s, smoothed.count - 1)
        }
        guard let band = best else { return (0.16, 0.68) }

        // Reach a little past the glare or shadow at either end.
        let pad = Double(band.1 - band.0 + 1) * 0.08
        let top = max(0, Double(band.0) - pad)
        let bottom = min(Double(H - 1), Double(band.1) + pad)
        return (y: top / Double(H), h: (bottom - top + 1) / Double(H))
    }

    // MARK: - Utility

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

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge1 > edge0 else { return x >= edge1 ? 1 : 0 }
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}

//
//  MarkerTracker.swift
//  Kotek
//
//  The other way to answer "which bilah, and when": put a retroreflective band
//  on the mallet and find it by brightness instead of by CoreML.
//
//  WHY THIS CAN WORK WHERE THE CLASSIFIER STRUGGLES. Retroreflective tape sends
//  light back along the axis it arrived on, so it only pays off when the lamp
//  sits beside the lens — which is exactly this app's rig: phone on a stand
//  above the gangsa, torch millimetres from the camera, mallet head facing up at
//  both. Under a shortened exposure (see `CameraController.setMarkerVision`) the
//  band clips to white while bronze, wood, cord and hands all fall away, and
//  finding the mallet stops being a recognition problem and becomes a threshold.
//
//  What that buys, in the order it matters:
//
//  - A DAMPING HAND IS NOT A CANDIDATE. It carries no marker, so the failure the
//    Schmitt trigger in VisionStrikeDetector spends its hysteresis working
//    around cannot arise here.
//  - THE ATTACK, NOT THE ARRIVAL. A presence model says the mallet is over the
//    bar, which is true from the moment it arrives and stays true while it
//    lingers — that is why the ear currently holds the timing. A tracked marker
//    has a trajectory, and the moment it turns around IS the impact.
//  - COST INDEPENDENT OF KEY COUNT. One pass over a downscaled frame, whatever
//    the figure touches. `StrikeFusion.activeKeys` exists because scoring ten
//    crops was most of the vision budget; there is nothing to restrict here.
//
//  AND HOW IT FAILS, which is the reason the classifier stays in the build. This
//  degrades to nothing rather than to less: a marker rolled out of view, hidden
//  under the hand, or an exposure wrong for the room yields no sighting at all,
//  where the CNN would still return a poor number. Marker mode is the exhibition
//  path; inference is what you fall back to when the room fights you.
//

import CoreGraphics
import Foundation

/// Which marker the tracker is looking for.
///
/// WHITE WAS THE WRONG DEFAULT and it is worth writing down why, because the
/// reasoning that produced it sounds right. A Balinese gangsa's frame is painted
/// red and gilded, so red looked like the colour most likely to be confused with
/// the instrument — and white retroreflective sheeting returns the most light.
/// Both true, and both beside the point: the test that follows from white is
/// "bright AND colourless", which is an exact description of a paper napkin
/// under a torch. Rooms are full of white things. Instruments are not full of
/// green ones.
///
/// A saturated retroreflector inverts the test into "bright AND strongly
/// coloured", and almost nothing else in a room is both at once — diffuse
/// coloured objects are coloured but dim, and the bright confusers (paper,
/// specular highlights, painted white) are bright but neutral.
nonisolated enum MarkerColour: Int, CaseIterable, Sendable {
    case white
    case red
    case green

    var name: String {
        switch self {
        case .white: return "white"
        case .red:   return "red"
        case .green: return "green"
        }
    }

    /// Green is the best of the three on a gangsa, if it can be sourced: the
    /// instrument is bronze, gold, red and black, so green appears nowhere on it
    /// — and a Bayer sensor carries twice as many green photosites as red or
    /// blue, so a green marker arrives with the best signal-to-noise of any
    /// colour before any processing at all.
    var note: String {
        switch self {
        case .white: return "bright but neutral — competes with paper, napkins, painted white"
        case .red:   return "good, except against the red-and-gold of a gangsa frame"
        case .green: return "best on a gangsa: nothing on the instrument is green"
        }
    }
}

// MARK: - Finding the marker in one frame

/// Nonisolated so the fusion actor can run it off the main thread, for the same
/// reason `MalletHitClassifier` is: this target defaults to MainActor isolation
/// and a per-frame image scan on the display link's thread is a stutter.
nonisolated final class MarkerTracker {

    /// One connected run of lit pixels. Coordinates are in ANALYSIS pixel space
    /// until `Sighting` normalises them.
    struct Blob {
        var area: Int
        var centroid: CGPoint
        var bounds: CGRect
    }

    /// What one frame had to say. All points/rects normalised 0–1 against the
    /// camera buffer, top-left origin — the same convention as everything else.
    struct Sighting {
        /// Largest first. Two is the design; more means the threshold is loose.
        var blobs: [Blob]
        /// Where the mallet actually touches the bar. With two markers this is
        /// extrapolated past the head along the shaft; with one it is just the
        /// blob's centre.
        var tip: CGPoint
        /// Apparent size of the head marker, √area normalised by frame width.
        ///
        /// This is not a diagnostic — it is the third coordinate. The camera
        /// looks straight down, so the mallet's descent is mostly motion ALONG
        /// the optical axis, which barely translates in the image and instead
        /// shows up as the marker getting smaller. A tracker watching x and y
        /// alone would see a strike as almost no movement at all.
        var scale: Double
        /// Share of analysed pixels that cleared the threshold. The number to
        /// set exposure by: a well-set frame is a fraction of a percent lit, and
        /// anything above a percent or two means the scene is coming through.
        var litFraction: Double
    }

    /// One frame's worth of answer, INCLUDING when the answer is "no marker".
    ///
    /// `find` used to return `Sighting?`, and a nil covered three unrelated
    /// situations that need three different fixes: nothing in frame was bright
    /// enough, something was bright enough but too coloured to be tape, or
    /// something passed both and was too small to be anything. On a bench that
    /// distinction is guessable. On a stand in a hall, twenty minutes before
    /// doors, it is the whole debugging session — so the numbers come back
    /// whether or not a mallet was found.
    struct Scan {
        var sighting: Sighting?
        /// The brightest channel value anywhere in the frame, and how far from
        /// neutral that pixel was. If `maxBrightness` sits below
        /// `brightnessThreshold` the exposure or the torch is the problem and no
        /// amount of threshold-fiddling will help.
        var maxBrightness = 0
        var spreadAtMaxBrightness = 0
        /// Pixels that cleared the brightness bar, and how many of those the
        /// colour test then threw away. With a coloured marker a large gap is
        /// EXPECTED and healthy — it is the room being rejected. With white it
        /// is the warning sign, because the thing being rejected may be the
        /// marker itself under a warm torch.
        var brightnessPassed = 0
        var colourRejected = 0
    }

    /// What colour of tape is on the mallet.
    var colour: MarkerColour = .red

    /// Brightness a pixel must reach, 0–255, measured on its BRIGHTEST CHANNEL
    /// rather than on luma.
    ///
    /// This was luma, and luma cannot see a coloured marker. Red tape with its
    /// red channel pegged at 255 and the others near 40 has a luma of about 104
    /// — so a threshold of 235 threw away a perfectly clipped marker before the
    /// colour test ever ran, and reported the same "nothing is bright enough" as
    /// a dark room. On the brightest channel it reads 255, which is what it
    /// physically is. For white tape the two measures agree, so nothing is lost.
    var brightnessThreshold: Int = 235
    /// …and how colourless it must be, as a raw hi−lo spread. Started at 40 on
    /// the theory that white tape returns white. It does not: the iPhone torch is
    /// distinctly warm, so a clipped marker reads more like (255, 235, 200) — a
    /// spread of 55 — and 40 threw the marker away while reporting the same "no
    /// blobs" as an unlit room. Hence both the looser default and the readout in
    /// `Scan` that tells the two apart.
    ///
    /// Only consulted for `.white`. White tape returns white; a gilded frame
    /// under a spotlight can be as BRIGHT as the marker but never as neutral, so
    /// this is what separates the two. It is also why the white roll is the one
    /// to use — a Balinese gangsa's frame is painted red and gold, which makes
    /// red the single worst colour to key against on this instrument.
    var saturationCeiling: Int = 70
    /// How far a COLOURED marker's channel must lead the others. The mirror of
    /// `saturationCeiling`, and the reason a red napkin-lit highlight does not
    /// qualify: a highlight is bright in all three channels at once.
    var saturationFloor: Int = 60
    /// Ignore everything above this fraction of the frame height.
    ///
    /// Top view never needed it — the camera sees the instrument and nothing
    /// else. A front view sees the whole room behind the player: visitors,
    /// lighting, an exit sign, someone in a red shirt. All of that sits ABOVE
    /// the instrument in frame, so one horizon line removes most of it, and it
    /// costs a smaller loop rather than more work.
    ///
    /// Set it generously. The mallet is raised well above the bars between
    /// strokes, and the approach is half of what the turnaround detector reads —
    /// cropping to just the bar line would leave it nothing to detect.
    var roiTop: Double = 0

    /// Blobs smaller than this are sensor noise and stray speculars.
    var minBlobArea: Int = 6
    /// How far past the head marker the tip sits, as a multiple of the gap
    /// between the two markers. Depends on where the bands are taped, so it is
    /// tunable rather than derived.
    var tipExtension: Double = 0.35

    /// Analysis width. The full 960×540 buffer is far more than a marker needs —
    /// a 3 cm band across a 60 cm instrument is still ~15 px at this size — and
    /// the scan is linear in pixel count.
    private let analysisWidth = 320

    private var analysisHeight = 0
    private var pixels: UnsafeMutablePointer<UInt8>?
    private var context: CGContext?
    private var labels: [Int32] = []

    deinit { pixels?.deallocate() }

    /// Find the mallet in one frame. `Scan.sighting` is nil when there was none;
    /// the rest of `Scan` says why.
    func scan(in image: CGImage) -> Scan {
        guard image.width > 0, image.height > 0 else { return Scan() }
        let w = analysisWidth
        let h = max(1, Int((Double(analysisWidth) * Double(image.height) / Double(image.width)).rounded()))
        guard let buffer = ensureBuffer(width: w, height: h),
              let ctx = context else { return Scan() }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // MARK: threshold + one-pass connected-component labelling
        //
        // Union-find rather than a flood fill: a flood fill recurses per blob and
        // its cost depends on blob SHAPE, which under a loose threshold (exactly
        // when you are tuning, and lit regions sprawl) is the worst case. This
        // pass is the same price whatever the frame contains.
        for i in labels.indices { labels[i] = 0 }
        var parent: [Int32] = [0]
        var litCount = 0
        var maxBrightness = 0, spreadAtMaxBrightness = 0, brightnessPassed = 0, colourRejected = 0

        func root(_ x: Int32) -> Int32 {
            var r = x
            while parent[Int(r)] != r { r = parent[Int(r)] }
            var c = x
            while parent[Int(c)] != c { let next = parent[Int(c)]; parent[Int(c)] = r; c = next }
            return r
        }

        let firstRow = min(max(0, Int(roiTop * Double(h))), h - 1)
        for y in firstRow..<h {
            let row = y * w
            for x in 0..<w {
                let idx = row + x
                let p = buffer + idx * 4
                let r = Int(p[0]), g = Int(p[1]), b = Int(p[2])
                let hi = max(r, max(g, b)), lo = min(r, min(g, b))
                if hi > maxBrightness {
                    maxBrightness = hi
                    spreadAtMaxBrightness = hi - lo
                }
                guard hi >= brightnessThreshold else { continue }
                brightnessPassed += 1

                // Cheap channel-dominance instead of a hue angle. Hue needs a
                // divide per pixel and buys nothing here: there are three
                // marker colours, not a continuum, and "is red clearly ahead of
                // the other two" is exactly the question.
                let accepted: Bool
                switch colour {
                case .white: accepted = hi - lo <= saturationCeiling
                case .red:   accepted = r == hi && r - max(g, b) >= saturationFloor
                case .green: accepted = g == hi && g - max(r, b) >= saturationFloor
                }
                guard accepted else {
                    colourRejected += 1
                    continue
                }
                litCount += 1

                let left = x > 0 ? labels[idx - 1] : 0
                let up = y > 0 ? labels[idx - w] : 0
                if left == 0 && up == 0 {
                    parent.append(Int32(parent.count))
                    labels[idx] = Int32(parent.count - 1)
                } else if left != 0 && up != 0 {
                    labels[idx] = min(left, up)
                    let a = root(left), bb = root(up)
                    if a != bb { parent[Int(max(a, bb))] = min(a, bb) }
                } else {
                    labels[idx] = max(left, up)
                }
            }
        }
        func result(_ sighting: Sighting?) -> Scan {
            Scan(sighting: sighting, maxBrightness: maxBrightness,
                 spreadAtMaxBrightness: spreadAtMaxBrightness,
                 brightnessPassed: brightnessPassed, colourRejected: colourRejected)
        }
        guard parent.count > 1 else { return result(nil) }

        // MARK: accumulate each component
        let n = parent.count
        var area = [Int](repeating: 0, count: n)
        var sumX = [Int](repeating: 0, count: n)
        var sumY = [Int](repeating: 0, count: n)
        var minX = [Int](repeating: .max, count: n)
        var maxX = [Int](repeating: .min, count: n)
        var minY = [Int](repeating: .max, count: n)
        var maxY = [Int](repeating: .min, count: n)

        for y in firstRow..<h {
            let row = y * w
            for x in 0..<w {
                let label = labels[row + x]
                guard label != 0 else { continue }
                let k = Int(root(label))
                area[k] += 1
                sumX[k] += x; sumY[k] += y
                if x < minX[k] { minX[k] = x }
                if x > maxX[k] { maxX[k] = x }
                if y < minY[k] { minY[k] = y }
                if y > maxY[k] { maxY[k] = y }
            }
        }

        var blobs: [Blob] = []
        for k in 1..<n where area[k] >= minBlobArea {
            blobs.append(Blob(
                area: area[k],
                centroid: CGPoint(x: Double(sumX[k]) / Double(area[k]),
                                  y: Double(sumY[k]) / Double(area[k])),
                bounds: CGRect(x: Double(minX[k]), y: Double(minY[k]),
                               width: Double(maxX[k] - minX[k] + 1),
                               height: Double(maxY[k] - minY[k] + 1))))
        }
        guard !blobs.isEmpty else { return result(nil) }
        blobs.sort { $0.area > $1.area }
        blobs = Array(blobs.prefix(2))

        // MARK: head, shaft, tip
        //
        // The larger band is the head — which is a taping instruction as much as
        // a heuristic, and the reason to wrap the head generously and keep the
        // shaft band narrow. Picking by image position instead does not survive
        // the player turning slightly, and picking by which is lower in frame
        // assumes a tilt the stand may not have.
        let head = blobs[0]
        var tip = head.centroid
        if blobs.count == 2 {
            let shaft = blobs[1]
            let dx = head.centroid.x - shaft.centroid.x
            let dy = head.centroid.y - shaft.centroid.y
            tip = CGPoint(x: head.centroid.x + dx * tipExtension,
                          y: head.centroid.y + dy * tipExtension)
        }

        func norm(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / Double(w), y: p.y / Double(h)) }
        let normalisedBlobs = blobs.map {
            Blob(area: $0.area,
                 centroid: norm($0.centroid),
                 bounds: CGRect(x: $0.bounds.minX / Double(w), y: $0.bounds.minY / Double(h),
                                width: $0.bounds.width / Double(w), height: $0.bounds.height / Double(h)))
        }

        return result(Sighting(blobs: normalisedBlobs,
                               tip: norm(tip),
                               scale: (Double(head.area).squareRoot()) / Double(w),
                               litFraction: Double(litCount) / Double(max(1, w * (h - firstRow)))))
    }

    /// One allocation for the life of the tracker. The frame size does not
    /// change mid-session, but a screen that re-enters with a different buffer
    /// size must not read the old one.
    private func ensureBuffer(width w: Int, height h: Int) -> UnsafeMutablePointer<UInt8>? {
        if let pixels, analysisHeight == h, context != nil { return pixels }
        pixels?.deallocate()
        let bytes = w * h * 4
        let fresh = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes)
        fresh.initialize(repeating: 0, count: bytes)
        guard let ctx = CGContext(data: fresh, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fresh.deallocate()
            return nil
        }
        //R NO flip here, and it is worth knowing why, because adding one looks
        //R obviously right. A bitmap context's user space has its origin at the
        //R bottom left, so the instinct is that a drawn image lands upside down
        //R relative to how these rows are indexed. It does not: row 0 of the
        //R backing buffer IS the image's top row, and `draw` already accounts
        //R for it. Measured, not assumed — a flip here mirrors every y, which
        //R puts each strike on the bilah opposite the one that was struck, and
        //R that is a symptom easy to blame on the alignment step instead.
        pixels = fresh
        context = ctx
        analysisHeight = h
        labels = [Int32](repeating: 0, count: w * h)
        return fresh
    }
}

// MARK: - Turning a trajectory into strikes

/// Fires when the tracked tip stops descending and comes back — which is the
/// impact, not the arrival over the bar.
nonisolated final class MarkerStrikeDetector {

    struct Turnaround {
        /// Where the tip was at the moment it reversed, buffer-normalised.
        let point: CGPoint
        /// When it reversed. NOT when this was detected: the reversal is only
        /// visible once the mallet has started back up, so a fire is reported
        /// about two frames late and timestamped to the sample that turned. The
        /// audio path has exactly the same shape and for the same reason — a
        /// strike cannot be confirmed until after it has happened.
        let hostTime: Double
        /// Speed on the way in, normalised units per sample. A hard stroke
        /// arrives faster than a hesitant one, so this stands in for confidence.
        let approachSpeed: Double
    }

    /// How fast the tip must be closing on the bar before a reversal counts,
    /// measured ALONG `descentAxis` rather than as raw speed — a mallet swept
    /// sideways fast is not a stroke. The floor is what stops a marker jittering
    /// in place from firing.
    var minApproachSpeed: Double = 0.004
    /// Refractory period. Matches `VisionStrikeDetector.minRearmSeconds` — about
    /// eight strokes a second, past what anyone plays and well inside the 250 ms
    /// a bundled figure leaves between strokes.
    var minRearmSeconds: Double = 0.09
    /// How much the apparent-size channel counts relative to translation. See
    /// `Sighting.scale`: overhead, most of a descent lives in this channel, so
    /// weighting it to zero would make a vertical strike invisible.
    var scaleWeight: Double = 1.0

    /// Which way is DOWN, towards the bar, in tracker coordinates.
    ///
    /// Without this the detector fired on any reversal at all, and a double
    /// stroke on one bilah produced THREE events: the two impacts, and the apex
    /// of the lift between them. An apex is a direction reversal by every test
    /// that ignores direction — the mallet stops going up and starts coming
    /// down — and it is exactly as sharp as an impact.
    ///
    /// Overhead the mallet descends AWAY from the lens, so the marker shrinks
    /// and `z` falls: down is (0, 0, -1). From the front the strike is an honest
    /// downward sweep: down is (0, +1, 0). A rig tilted between the two would
    /// want a blend, which is why this is a vector and not a flag.
    var descentAxis: (x: Double, y: Double, z: Double) = (0, 0, -1)
    /// A gap longer than this means the marker was lost, and the samples either
    /// side of the gap describe two different gestures.
    var maxSampleGap: Double = 0.2

    private struct Sample { var x: Double; var y: Double; var z: Double; var t: Double }
    private var samples: [Sample] = []
    private var lastFireTime: Double = -1

    func reset() {
        samples.removeAll(keepingCapacity: true)
        lastFireTime = -1
    }

    func process(tip: CGPoint, scale: Double, at hostTime: Double) -> Turnaround? {
        if let last = samples.last, hostTime - last.t > maxSampleGap { samples.removeAll(keepingCapacity: true) }
        samples.append(Sample(x: tip.x, y: tip.y, z: scale * scaleWeight, t: hostTime))
        if samples.count > 5 { samples.removeFirst(samples.count - 5) }
        guard samples.count == 5 else { return nil }

        // Two-sample spans rather than adjacent differences: at 30 fps a single
        // frame of tracking noise is a large share of the movement between two
        // frames, and adjacent differencing turned that noise into phantom
        // reversals on a mallet that was travelling perfectly straight.
        //
        // Projected onto the descent axis, so what is being asked is "was it
        // closing on the bar, and has it now stopped" rather than the
        // direction-blind "did it turn round".
        let depth = samples.map { $0.x * descentAxis.x + $0.y * descentAxis.y + $0.z * descentAxis.z }
        let closing = depth[2] - depth[0]
        let leaving = depth[4] - depth[2]
        guard closing >= minApproachSpeed, leaving < 0 else { return nil }

        // The DEEPEST sample in the window, not always the middle one.
        //
        // Taking samples[2] on faith fired a frame early and always in the same
        // direction: the two-sample span straddles the true minimum, so it flips
        // sign as soon as the far end starts to rise, which is before the near
        // end has got there. A systematic 33 ms bias is small against a ±112 ms
        // Perfect window but it is free to remove, and a bias is exactly what
        // the "vs onset" readout would otherwise show as the marker path's
        // permanent handicap.
        var pivotIndex = 0
        for i in 1..<samples.count where depth[i] > depth[pivotIndex] { pivotIndex = i }
        let pivot = samples[pivotIndex]

        guard lastFireTime < 0 || pivot.t - lastFireTime >= minRearmSeconds else { return nil }
        lastFireTime = pivot.t
        return Turnaround(point: CGPoint(x: pivot.x, y: pivot.y),
                          hostTime: pivot.t,
                          approachSpeed: closing)
    }

}

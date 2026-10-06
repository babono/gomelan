//
//  MarkerFusion.swift
//  Kotek
//
//  The marker path's counterpart to `StrikeFusion`: pulls the newest camera
//  frame, finds the mallet marker in it, and reconciles the tip with the
//  calibrated key layout. Same contract, same coordinate spaces, so the two
//  detectors are genuinely swappable behind one toggle.
//
//  An ACTOR for the same reason StrikeFusion is one — the scan is a per-frame
//  pass over a downscaled image, and this target's default MainActor isolation
//  would put it on the display link's thread.
//
//  The difference worth noticing against StrikeFusion: there is no per-key work
//  here at all. Vision still answers "which key by location", but the location
//  comes from where the marker IS rather than from which crop we chose to score,
//  so the cost does not grow with the number of bilah in the figure.
//

import CoreGraphics
import QuartzCore

/// Where the phone is looking from.
///
/// The two views trade the same two problems in opposite directions, which is
/// why this is a mode rather than a migration.
///
/// TOP makes key identity trivial and timing hard. The bilah are full rectangles
/// and the marker either sits on one or does not; but the mallet's descent is
/// motion along the optical axis, so it barely translates and shows up mostly as
/// the marker getting smaller — the noisiest channel available.
///
/// FRONT inverts both. The strike becomes an honest downward sweep, so the
/// turnaround is far better resolved, which is the half that currently leans on
/// the microphone. In exchange the bilah are foreshortened slivers and the whole
/// room stands behind the player, in frame.
///
/// The saving grace for FRONT is a fact about pinhole projection that is easy to
/// doubt: image-x depends on lateral offset and depth, NOT height. A marker held
/// 5 cm above the bar it is about to strike projects to the same x as the
/// contact point. So identity collapses from "which rect contains the tip" to
/// "which vertical band contains its x" — one dimension instead of two.
nonisolated enum MarkerPOV: Int, CaseIterable, Sendable {
    case top
    case front

    var name: String { self == .top ? "top" : "front" }
}

actor MarkerFusion {

    struct Event {
        let keyIndex: Int
        let hostTime: Double
        /// Rough confidence. The marker path has no probability to report — it
        /// either found the mallet or it did not — so this stands in for one:
        /// a two-band sighting is trusted more than a single band, because the
        /// pair also proved its own geometry.
        let confidence: Double
    }

    /// Everything one polled frame produced, including when it produced no
    /// strike. The debug screen needs the difference between "no marker in
    /// frame", "marker seen, not moving" and "marker turned around off the
    /// keys" — collapsing those into an optional Event is the same mistake
    /// `StrikeFusion.scoresAt` exists to undo.
    struct Frame {
        var hostTime: Double
        /// Overlay-normalised, ready to draw straight onto the preview.
        var tip: CGPoint?
        var blobs: [CGRect] = []
        var litFraction: Double = 0
        var event: Event?
        /// Why there was no marker, when there was none. Passed straight through
        /// from the tracker — see `MarkerTracker.Scan`.
        var maxBrightness = 0
        var spreadAtMaxBrightness = 0
        var brightnessPassed = 0
        var colourRejected = 0
    }

    private let frames: FrameBuffer
    private let keys: [InstrumentKey]
    private let tracker = MarkerTracker()
    private let strikes = MarkerStrikeDetector()

    private var viewSize: CGSize
    private var pov: MarkerPOV = .top

    /// Front-view band geometry: the x extent the bilah span, an optional
    /// left-right mirror, and a bulge term.
    ///
    /// `skew` exists because a fronto-parallel row of bars projects to EVENLY
    /// spaced bands — perspective does not distort a row all at one depth — but
    /// a phone set down slightly off-axis or turned a few degrees breaks that
    /// assumption, and it will be. One parameter that widens the near end at the
    /// far end's expense covers the common case without asking anyone to drag
    /// nine dividers on a debug screen.
    private var bandLeft = 0.05
    private var bandRight = 0.95
    private var bandSkew = 0.0
    /// Whether key 0 is on the right. Which end the phone sits at decides this,
    /// and it is a coin flip.
    private var bandFlip = false
    /// The play loop polls faster than the camera delivers; without this the
    /// same frame is scanned twice and fed to the trajectory twice, which reads
    /// as a mallet that stopped dead.
    private var lastScannedHostTime: Double = -1
    /// Where the marker was on that scan, nil when there was none. Kept so the
    /// gate can answer without scanning a second time — the classifier path
    /// polls this at its own slower rate, and re-running the pass per strike
    /// would put a full image scan inside the decision.
    private var lastTip: CGPoint?

    init(frames: FrameBuffer, keys: [InstrumentKey], viewSize: CGSize) {
        self.frames = frames
        self.keys = keys
        self.viewSize = viewSize
    }

    func setViewSize(_ size: CGSize) { viewSize = size }

    func setBrightnessThreshold(_ value: Int) { tracker.brightnessThreshold = value }
    func setColour(_ value: MarkerColour) { tracker.colour = value }
    func setSaturationFloor(_ value: Int) { tracker.saturationFloor = value }
    func setROITop(_ value: Double) { tracker.roiTop = value }

    /// Front view reads the strike from translation, so apparent size stops
    /// being the channel that carries it and becomes mostly noise. Not zero —
    /// the mallet does move toward the camera — but nothing like the weight it
    /// has to hold from overhead.
    func setPOV(_ value: MarkerPOV) {
        pov = value
        strikes.scaleWeight = value == .top ? 1.0 : 0.25
        // Overhead the mallet descends away from the lens and the marker
        // shrinks; from the front it simply falls. See `descentAxis`.
        strikes.descentAxis = value == .top ? (0, 0, -1) : (0, 1, 0)
    }

    func setBands(left: Double, right: Double, skew: Double, flip: Bool) {
        bandLeft = left
        bandRight = right
        bandSkew = skew
        bandFlip = flip
    }

    /// The N+1 band edges, in overlay-normalised x. Computed forward and
    /// searched rather than inverting the skew warp — the inverse is a quadratic
    /// with a sign choice, and this runs a handful of times a second on ten
    /// bands, so the closed form buys nothing but a way to be subtly wrong.
    func bandEdges() -> [Double] {
        let n = max(1, keys.count)
        return (0...n).map { i in
            let u = Double(i) / Double(n)
            let warped = u + bandSkew * u * (1 - u)
            return bandLeft + (bandRight - bandLeft) * warped
        }
    }
    func setMinApproachSpeed(_ value: Double) { strikes.minApproachSpeed = value }
    func setTipExtension(_ value: Double) { tracker.tipExtension = value }
    func setSaturationCeiling(_ value: Int) { tracker.saturationCeiling = value }

    func reset() {
        strikes.reset()
        lastScannedHostTime = -1
        lastTip = nil
    }

    /// Scan the newest unscanned frame. Returns nil when the view has not laid
    /// out, no frame is buffered, or the newest one has already been scanned.
    func poll() -> Frame? {
        guard viewSize.width > 0, viewSize.height > 0,
              let frame = frames.nearest(to: CACurrentMediaTime()),
              frame.hostTime != lastScannedHostTime else { return nil }
        lastScannedHostTime = frame.hostTime

        let scan = tracker.scan(in: frame.image)
        guard let sighting = scan.sighting else {
            // A frame with no marker still advances time. Left unsaid, the
            // trajectory would stitch together the moments either side of an
            // occlusion into one implausible movement.
            lastTip = nil
            return Frame(hostTime: frame.hostTime, tip: nil,
                         maxBrightness: scan.maxBrightness,
                         spreadAtMaxBrightness: scan.spreadAtMaxBrightness,
                         brightnessPassed: scan.brightnessPassed, colourRejected: scan.colourRejected)
        }

        let overlayTip = overlayPoint(sighting.tip, bufferSize: frame.size)
        lastTip = overlayTip
        var out = Frame(hostTime: frame.hostTime,
                        tip: overlayTip,
                        blobs: sighting.blobs.map { overlayRect($0.bounds, bufferSize: frame.size) },
                        litFraction: sighting.litFraction,
                        maxBrightness: scan.maxBrightness,
                        spreadAtMaxBrightness: scan.spreadAtMaxBrightness,
                        brightnessPassed: scan.brightnessPassed, colourRejected: scan.colourRejected)

        if let turn = strikes.process(tip: sighting.tip, scale: sighting.scale, at: frame.hostTime) {
            let point = overlayPoint(turn.point, bufferSize: frame.size)
            if let key = keyContaining(point) {
                out.event = Event(keyIndex: key,
                                  hostTime: turn.hostTime,
                                  confidence: sighting.blobs.count >= 2 ? 1.0 : 0.7)
            }
            // A turnaround off the keys is a real gesture — lifting the mallet,
            // reaching across — and is deliberately dropped rather than snapped
            // to the nearest bar. Snapping was tried on the classifier path and
            // is how a rest becomes a wrong-key.
        }
        return out
    }

    /// Which bilah the tip is over, or nil if it is over none.
    ///
    /// Tested against `rect` rather than the free-corner `corners` quad, to stay
    /// consistent with detection everywhere else in the app — the crop mapper
    /// uses the bounding box too, so a quad here would mean the two halves of
    /// vision disagreed about where a key is.
    private func keyContaining(_ p: CGPoint) -> Int? {
        switch pov {
        case .top:
            for key in keys where key.rect.cgRect.contains(p) { return key.index }
            return nil
        case .front:
            let edges = bandEdges()
            guard keys.count > 0, edges.count == keys.count + 1 else { return nil }
            for i in 0..<keys.count where p.x >= edges[i] && p.x < edges[i + 1] {
                return keys[bandFlip ? keys.count - 1 - i : i].index
            }
            return nil
        }
    }

    /// Whether a marker was seen over `keyIndex` at roughly `hostTime` — the
    /// question the classifier path asks when the marker is acting as a gate
    /// rather than as the detector.
    ///
    /// Deliberately answers with a REASON. "The gate rejected it" covers a
    /// mallet that was somewhere else entirely, a mallet that was not in frame,
    /// and a marker scan too old to speak for the moment in question, and those
    /// three want different fixes.
    enum Gate: Equatable {
        case allow
        case noScan
        case stale(Double)
        case noMallet
        case elsewhere(Int?)
    }

    func gate(keyIndex: Int, at hostTime: Double, margin: Double, within: Double) -> Gate {
        guard lastScannedHostTime >= 0 else { return .noScan }
        let age = abs(hostTime - lastScannedHostTime)
        guard age <= within else { return .stale(age) }
        guard let tip = lastTip else { return .noMallet }
        switch pov {
        case .top:
            guard let key = keys.first(where: { $0.index == keyIndex }) else { return .allow }
            let box = key.rect.cgRect.insetBy(dx: -margin, dy: -margin)
            return box.contains(tip) ? .allow : .elsewhere(keyContaining(tip))
        case .front:
            let edges = bandEdges()
            guard keys.count > 0, edges.count == keys.count + 1,
                  let slot = (0..<keys.count).first(where: {
                      keys[bandFlip ? keys.count - 1 - $0 : $0].index == keyIndex
                  }) else { return .allow }
            return (tip.x >= edges[slot] - margin && tip.x < edges[slot + 1] + margin)
                ? .allow : .elsewhere(keyContaining(tip))
        }
    }

    private func overlayPoint(_ p: CGPoint, bufferSize: CGSize) -> CGPoint {
        CropMapper.overlayPoint(bufferNormalized: p, bufferSize: bufferSize, viewSize: viewSize)
    }

    private func overlayRect(_ r: CGRect, bufferSize: CGSize) -> CGRect {
        let mapped = CropMapper.overlayRect(
            bufferNormalized: NormalizedRect(x: r.minX, y: r.minY, w: r.width, h: r.height),
            bufferSize: bufferSize, viewSize: viewSize)
        return mapped.cgRect
    }
}

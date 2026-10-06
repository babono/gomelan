//
//  FrameBuffer.swift
//  Kotek
//
//  A short rolling history of camera frames, keyed by host time.
//
//  Audio reports a strike ~105ms AFTER it physically happens (see
//  AudioEngineController), with a hostTime reconstructed to when the strike
//  actually occurred. So the video frame that shows the strike is already in the
//  past by the time the audio callback fires. This buffer keeps the last handful
//  of frames so the fusion layer can look one up by that hostTime.
//
//  Each frame is rendered once to an immutable CGImage rather than retaining the
//  raw CVPixelBuffer: the capture output uses alwaysDiscardsLateVideoFrames with
//  a small pool, and holding onto its buffers would starve it and drop frames.
//

import CoreImage
import CoreVideo
import CoreGraphics

/// Written on the capture queue, read from the fusion actor — the NSLock is the
/// synchronisation, hence the unchecked conformance.
nonisolated final class FrameBuffer: @unchecked Sendable {

    struct Frame {
        let image: CGImage
        /// CACurrentMediaTime-clock seconds — same clock the audio strike carries.
        let hostTime: Double
        /// Pixel dimensions of `image`, for the aspect-fill crop mapping.
        let size: CGSize
    }

    private let capacity: Int
    private var frames: [Frame] = []
    private let lock = NSLock()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// ~8 frames ≈ 270ms at 30fps — covers the audio's ~105ms delay plus jitter.
    /// Each frame is a rendered image, so the count is also a memory budget.
    init(capacity: Int = 8) {
        self.capacity = capacity
    }

    /// Called on the capture session queue for every delivered frame.
    func ingest(pixelBuffer: CVPixelBuffer, hostTime: Double) {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }
        let frame = Frame(image: cg, hostTime: hostTime, size: ci.extent.size)

        lock.lock()
        defer { lock.unlock() }
        frames.append(frame)
        if frames.count > capacity {
            frames.removeFirst(frames.count - capacity)
        }
    }

    /// The buffered frame closest in time to `hostTime`, or nil if empty.
    func nearest(to hostTime: Double) -> Frame? {
        lock.lock()
        defer { lock.unlock() }
        return frames.min { abs($0.hostTime - hostTime) < abs($1.hostTime - hostTime) }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        frames.removeAll(keepingCapacity: true)
    }
}

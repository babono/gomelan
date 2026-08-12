//
//  DisplayLink.swift
//  gomelan
//
//  A CADisplayLink wrapper. Frame-accurate timing matters for a rhythm game, so
//  the play loop is driven from a display link rather than a Timer (PRD §13.5).
//

import QuartzCore

final class DisplayLink {
    /// Called each frame on the main thread with the current host time (seconds).
    var onFrame: ((Double) -> Void)?

    private var link: CADisplayLink?
    private let proxy = Proxy()

    func start() {
        guard link == nil else { return }
        proxy.onFrame = { [weak self] in self?.onFrame?(CACurrentMediaTime()) }
        let link = CADisplayLink(target: proxy, selector: #selector(Proxy.step))
        //R Cap at 60Hz. On a ProMotion screen this would otherwise tick — and
        //R redraw the whole guidance layer — 120 times a second, for timing
        //R windows measured in hundreds of milliseconds.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    /// Keeps the CADisplayLink target off the owning object to avoid a retain
    /// cycle (CADisplayLink retains its target).
    private final class Proxy: NSObject {
        var onFrame: (() -> Void)?
        @objc func step() { onFrame?() }
    }
}

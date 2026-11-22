//
//  DisplayLink.swift
//  Kotek
//
//  A CADisplayLink wrapper. Frame-accurate timing matters for a rhythm game, so
//  the play loop is driven from a display link rather than a Timer (PRD §13.5).
//

import QuartzCore

final class DisplayLink {
    /// Called each frame on the main thread with the host time (seconds) the
    /// frame will be on screen.
    var onFrame: ((Double) -> Void)?

    private var link: CADisplayLink?
    private let proxy = Proxy()

    func start() {
        guard link == nil else { return }
        // When the frame will be SHOWN, not when the callback happens to run.
        // It was `CACurrentMediaTime()`, and the callback's place in the frame
        // moves whenever ProMotion changes rate — as it does for any SwiftUI
        // animation, such as the cycle number ticking over in the title — so
        // for a few frames every note was drawn for the wrong instant: the
        // falling notes jumped at the turn of every cycle. The simulator has
        // one fixed rate and never showed it.
        proxy.onFrame = { [weak self] time in self?.onFrame?(time) }
        let link = CADisplayLink(target: proxy, selector: #selector(Proxy.step))
        // Cap at 60Hz to avoid redundant redraws on ProMotion screens.
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
        var onFrame: ((Double) -> Void)?
        @objc func step(_ link: CADisplayLink) {
            onFrame?(link.targetTimestamp)
        }
    }
}

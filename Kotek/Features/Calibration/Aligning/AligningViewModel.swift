//
//  AligningViewModel.swift
//  Kotek
//
//  Created by Dimas Nugraha on 05/10/26.
//

import CoreGraphics
import FactoryKit
import Foundation
import SwiftUI

@Observable
@MainActor
final class AligningViewModel {
    var app: AppState { Container.shared.router() }

    let camera: CameraController

    var keys: [InstrumentKey] = []
    /// The overlay's on-screen size, needed to map detector rects (buffer space)
    /// back into this view's coordinate space.
    var overlaySize: CGSize = .zero
    var detecting = false
    var status =
        "Drag a mask to move it · drag an edge handle to resize"
    var selectedIndex: Int?
    /// The corner currently being resized (overlay-normalised), for the magnifier.
    /// Only set while resizing — plain moves don't zoom.
    var dragFocus: CGPoint?
    /// Whether the row-level fit controls are revealed (behind the spanner).
    var showAdjust = false
    /// Non-nil while the fit is being committed — see `confirmAlignment`.
    var busyMessage: String?

    init(cameraService: CameraController = Container.shared.cameraService()) {
        self.camera = cameraService
    }

    /// Initializes keys and runs auto-fit if arriving from framing or first run.
    func setup() {
        var fromFraming = false
        if keys.isEmpty {
            // Coming from framing, start inside the area just framed — the
            // saved fit belongs to wherever the instrument was last time.
            fromFraming = app.seedMasksFromFraming
            keys =
                fromFraming
                ? InstrumentProfile.layout(
                    count: app.profile.keyCount,
                    in: app.framedRegion
                )
                : app.profile.keys
            app.seedMasksFromFraming = false
        }

        let shouldAutoFit = fromFraming || keys.isEmpty
        if !shouldAutoFit {
            status =
                "Your saved fit — drag to adjust, or Auto-detect to start over"
        }

        Task {
            busyMessage =
                shouldAutoFit ? "Finding your keys…" : "Waking the camera…"
            let started = CACurrentMediaTime()
            if shouldAutoFit {
                await autoDetect(requireAll: true)
            }

            let minimumVisible = 1.4 - (CACurrentMediaTime() - started)
            if minimumVisible > 0 {
                try? await Task.sleep(for: .seconds(minimumVisible))
            }
            busyMessage = nil
        }
    }

    /// Resets all keys back to an evenly spaced row.
    func resetFit() {
        keys = InstrumentProfile.layout(count: keys.count)
        status = "Reset to an even row — drag to fit"
    }

    // MARK: - Auto-detect (Vision rectangle detection, one-shot)

    /// Detect bilah edges in the current frame and snap the masks onto them. The
    /// user can still drag/resize afterwards; "Reset fit" restores an even row.
    ///
    /// `requireAll` is for the automatic pass on arrival: leave the row you
    /// framed alone unless every bilah can be placed. Tapping Auto-detect is an
    /// explicit ask, so a partial snap is welcome there.
    func autoDetect(requireAll: Bool = false) async {
        guard let frame = await waitForFrame() else {
            if !requireAll {
                status = "No camera frame yet — try Auto-detect again"
            }
            return
        }
        detecting = true
        defer { detecting = false }

        let need = max(3, keys.count / 2)

        // 1) The comb fit inside the framed region: it knows the count, the
        //    region and that the row is periodic, so it is the one worth trying
        //    first. See BilahFinder.
        var placed = findInFramedRegion(frame: frame)

        // 2) Otherwise the trained detector (or the generic rectangle fallback),
        //    searching the whole frame.
        if placed.count < need {
            let raw = await KeyDetector.detectKeys(
                in: frame.image,
                minimumAspectRatio: 0.3,
                minimumSize: 0.03
            )
            placed = barCandidates(from: raw, bufferSize: frame.size)
        }

        // 3) Failing that, the luminance column profile over the whole frame.
        if placed.count < need {
            let proj = ProjectionAligner.detect(
                in: frame.image,
                count: keys.count
            )
            .map {
                CropMapper.overlayRect(
                    bufferNormalized: $0,
                    bufferSize: frame.size,
                    viewSize: overlaySize
                )
            }
            .sorted { $0.cgRect.midX < $1.cgRect.midX }
            if proj.count >= need { placed = proj }
        }

        let n = min(keys.count, placed.count)
        guard placed.count >= need, !requireAll || n == keys.count else {
            if !requireAll {
                status = "Use the controls below to fit your \(keys.count) keys"
            }
            return
        }

        for i in 0..<n {
            keys[i].rect = placed[i]
        }
        status =
            n == keys.count
            ? "Snapped all \(keys.count) keys — nudge any that are off"
            : "Snapped \(n) of \(keys.count) — fit the rest with the controls"
    }

    /// The newest camera frame, waiting for one if the session has only just
    /// been handed over — and for the overlay to have a size, since every rect
    /// is mapped through it. Polls rather than sleeping a fixed guess: arriving
    /// from framing the camera is already running, so this usually returns on
    /// the first try.
    func waitForFrame(timeout: Double = 2) async -> FrameBuffer.Frame? {
        let deadline = CACurrentMediaTime() + timeout
        while CACurrentMediaTime() < deadline {
            if overlaySize.width > 0,
                let frame = camera.frameBuffer.nearest(to: CACurrentMediaTime())
            {
                return frame
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return nil
    }

    /// Crop the frame to the area the player framed the instrument into, fit the
    /// comb there, and map the result back into overlay space.
    ///
    /// The crop IS the region, so the mapping back is a plain scale-and-offset —
    /// no aspect-fill maths, and no chance of the two disagreeing.
    func findInFramedRegion(frame: FrameBuffer.Frame)
        -> [NormalizedRect]
    {
        let region = app.framedRegion
        let bufferRect = CropMapper.bufferRect(
            overlay: region,
            bufferSize: frame.size,
            viewSize: overlaySize
        )
        guard let crop = MalletHitClassifier.crop(frame.image, to: bufferRect)
        else { return [] }

        return BilahFinder.find(in: crop, count: keys.count).map { r in
            NormalizedRect(
                x: region.x + r.x * region.w,
                y: region.y + r.y * region.h,
                w: r.w * region.w,
                h: r.h * region.h
            )
        }
    }

    /// Map detector rects into overlay space, keep the vertical bar-like ones
    /// inside the frame, sort left-to-right, and suppress duplicates.
    func barCandidates(from raw: [NormalizedRect], bufferSize: CGSize)
        -> [NormalizedRect]
    {
        var mapped: [NormalizedRect] = []
        for r in raw {
            let o = CropMapper.overlayRect(
                bufferNormalized: r,
                bufferSize: bufferSize,
                viewSize: overlaySize
            )
            if isBarLike(o) { mapped.append(o) }
        }
        mapped.sort { $0.cgRect.midX < $1.cgRect.midX }

        // Non-max suppression on centre-x: one physical bar can yield several
        // overlapping rectangles; keep the largest of any cluster.
        var kept: [NormalizedRect] = []
        for c in mapped {
            if let last = kept.last,
                abs(last.cgRect.midX - c.cgRect.midX) < max(c.w, last.w) * 0.6
            {
                if (c.w * c.h) > (last.w * last.h) { kept[kept.count - 1] = c }
                continue
            }
            kept.append(c)
        }
        return kept
    }

    /// A plausible bilah mask. Any backend must land inside the frame; the generic
    /// rectangle fallback additionally must look like a vertical bar, to reject the
    /// wooden frame and rope edges. A trained detector is trusted on shape.
    func isBarLike(_ r: NormalizedRect) -> Bool {
        guard r.w > 0.01, r.h > 0.01,
            r.x > -0.1, r.y > -0.1,
            r.x + r.w < 1.1, r.y + r.h < 1.1
        else { return false }
        if KeyDetector.usesTrainedDetector { return true }
        guard r.h > r.w else { return false }
        return r.w < 0.3 && r.h > 0.08 && r.h < 0.95
    }

    /// Committing the fit is not instant: the profile is written to disk and the
    /// lens is locked to focus and exposure, and the lock in particular takes the
    /// hardware a moment. It used to fire and forget, so the next screen appeared
    /// while the camera was still settling. Now the wait is shown and awaited.
    func confirmAlignment() {
        guard busyMessage == nil else { return }
        busyMessage = "Saving the fit…"

        var profile = app.profile
        profile.keys = keys
        app.profile = profile

        Task {
            await app.saveProfileAsync()
            await camera.lockFocusAndExposureAsync()
            //R Deliberately NOT cleared before navigating: the baseline screen
            //R has its own warm-up, and dropping the scrim here would show this
            //R screen bare for a frame before it goes.
            app.alignmentConfirmed()
        }
    }

    /// Binding to directly access and mutate a key's axis-aligned rect.
    func rectBinding(_ index: Int) -> Binding<NormalizedRect> {
        Binding(
            get: { self.keys[index].rect },
            set: { self.keys[index].rect = $0 }
        )
    }

    // MARK: - Row-level fit controls

    /// Adjust every mask together — the fast path: Reset to an even row, set the
    /// width/height/spacing to match the bars, then fine-tune individuals by drag.

    /// Resize all masks around their own centres.
    func adjustWidth(_ delta: Double) {
        for i in keys.indices {
            let center = keys[i].rect.x + keys[i].rect.w / 2
            let w = min(0.4, max(0.02, keys[i].rect.w + delta))
            keys[i].rect.w = w
            keys[i].rect.x = center - w / 2
        }
    }

    func adjustHeight(_ delta: Double) {
        for i in keys.indices {
            let center = keys[i].rect.y + keys[i].rect.h / 2
            let h = min(0.95, max(0.05, keys[i].rect.h + delta))
            keys[i].rect.h = h
            keys[i].rect.y = center - h / 2
        }
    }

    /// Spread (>1) or tighten (<1) the whole row around its centre.
    func adjustSpacing(_ factor: Double) {
        guard !keys.isEmpty else { return }
        let centers = keys.map { $0.rect.x + $0.rect.w / 2 }
        let mean = centers.reduce(0, +) / Double(centers.count)
        for i in keys.indices {
            let newCenter = mean + (centers[i] - mean) * factor
            keys[i].rect.x = newCenter - keys[i].rect.w / 2
        }
    }

    /// Move the whole row up (−) or down (+).
    func nudgeRow(_ delta: Double) {
        for i in keys.indices { keys[i].rect.y += delta }
    }
}

//
//  AligningView.swift
//  gomelan
//
//  Setup step 3/3 (PRD §13.4 .aligning). The bundled bilah masks are overlaid
//  and draggable — the carved, gilded frame is visually busy, so manual
//  drag-adjust is not optional polish (§3.2). Confirming locks focus/exposure
//  (§6.2) and leads into the baseline.
//

import SwiftUI

struct AligningView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController

    @State private var keys: [InstrumentKey] = []
    /// The overlay's on-screen size, needed to map detector rects (buffer space)
    /// back into this view's coordinate space.
    @State private var overlaySize: CGSize = .zero
    @State private var detecting = false
    @State private var status = "Drag to move · drag an edge handle to adjust size"
    @State private var selectedIndex: Int?
    /// The corner currently being resized (overlay-normalised), for the magnifier.
    /// Only set while resizing — plain moves don't zoom.
    @State private var dragFocus: CGPoint?
    /// Whether the row-level fit controls are revealed (behind the spanner).
    @State private var showAdjust = false

    var body: some View {
        ZStack {
            // Full-bleed camera fills the whole screen.
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.22).ignoresSafeArea())

            // Masks + loupe live in the same full-bleed coordinate space as the
            // camera, so normalised rects map straight onto what's shown.
            GeometryReader { geo in
                Color.clear
                    .onAppear { overlaySize = geo.size }
                    .onChange(of: geo.size) { _, new in overlaySize = new }

                let sortedIndices = keys.indices.sorted { i1, i2 in
                    if selectedIndex == i1 { return false }
                    if selectedIndex == i2 { return true }
                    return i1 < i2
                }

                ForEach(sortedIndices, id: \.self) { i in
                    RectMask(rect: rectBinding(i),
                             viewSize: geo.size,
                             label: bilahLabel(keys[i].index, count: keys.count),
                             isSelected: selectedIndex == i,
                             onSelect: { selectedIndex = i },
                             onResizeFocus: { dragFocus = $0 })
                }

                // Magnifier — only while resizing, at the corner being pulled.
                if let focus = dragFocus,
                   let frame = camera.frameBuffer.nearest(to: CACurrentMediaTime()) {
                    MagnifierLoupe(focus: focus,
                                   image: frame.image,
                                   bufferSize: frame.size,
                                   viewSize: geo.size)
                        .position(x: min(max(focus.x * geo.size.width, 92), geo.size.width - 92),
                                  y: 96)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
            .coordinateSpace(name: "alignSpace")

            // Chrome floats on top, inset from the notch, over translucent scrims.
            VStack(spacing: 0) {
                TopBar(title: "Fit the mask to your bilah",
                       backTitle: "Rescan",
                       onBack: { app.screen = .framing },
                       trailingText: "3 / 3",
                       tint: Theme.cream, accent: Theme.copper,
                       compact: true)
                    .background(
                        LinearGradient(colors: [.black.opacity(0.5), .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea(edges: .top)
                    )
                Spacer()
                if showAdjust { adjustBar }
                bottomBar
            }
        }
        .onAppear {
            camera.start()
            if keys.isEmpty { keys = app.profile.keys }
            // Let the session deliver a frame, then seed the masks from the camera.
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                await autoDetect()
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            if detecting { ProgressView().tint(Theme.copper) }
            Text(status)
                .font(.sans(13))
                .foregroundStyle(Theme.inkStone)
                .lineLimit(1)

            Spacer()

            Button("Reset fit") {
                keys = InstrumentProfile.layout(count: keys.count)
                status = "Reset to an even row — drag to fit"
            }
            .font(.sans(13, weight: .medium))
            .foregroundStyle(Theme.inkStone)
            .underline()
            .buttonStyle(.plain)

            // Spanner: reveal/hide the row-level fit controls.
            Button {
                withAnimation(.snappy(duration: 0.2)) { showAdjust.toggle() }
            } label: {
                Image(systemName: "wrench.adjustable")
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(showAdjust ? Theme.ink : Theme.copper)
                    .frame(width: 38, height: 38)
                    .background(showAdjust ? Theme.copper : .clear, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.copper.opacity(0.6), lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            PillButton(title: "Auto-detect", style: .outlined, tint: Theme.copper, compact: true) {
                Task { await autoDetect() }
            }
            .disabled(detecting)

            PillButton(title: "Calibrate", style: .filled, tint: Theme.copper, compact: true) {
                confirmAlignment()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Auto-detect (Vision rectangle detection, one-shot)

    /// Detect bilah edges in the current frame and snap the masks onto them. The
    /// user can still drag/resize afterwards; "Reset fit" restores an even row.
    private func autoDetect() async {
        guard overlaySize.width > 0,
              let frame = camera.frameBuffer.nearest(to: CACurrentMediaTime()) else {
            status = "No camera frame yet — try Auto-detect again"
            return
        }
        detecting = true
        defer { detecting = false }

        let need = max(3, keys.count / 2)

        // 1) The trained detector (or the generic rectangle fallback).
        let raw = await KeyDetector.detectKeys(in: frame.image,
                                               minimumAspectRatio: 0.3,
                                               minimumSize: 0.03)
        var placed = barCandidates(from: raw, bufferSize: frame.size)

        // 2) If that found too few, try the model-free column-profile aligner,
        //    which is tuned to this instrument's bright-bar / dark-gap structure.
        if placed.count < need {
            let proj = ProjectionAligner.detect(in: frame.image, count: keys.count)
                .map { CropMapper.overlayRect(bufferNormalized: $0, bufferSize: frame.size, viewSize: overlaySize) }
                .sorted { centerX($0) < centerX($1) }
            if proj.count >= need { placed = proj }
        }

        guard placed.count >= need else {
            status = "Use the controls below to fit your \(keys.count) bilah"
            return
        }

        let n = min(keys.count, placed.count)
        for i in 0..<n { keys[i].rect = placed[i]; keys[i].corners = nil }
        status = n == keys.count
            ? "Snapped all \(keys.count) bilah — nudge any that are off"
            : "Snapped \(n) of \(keys.count) — fit the rest with the controls"
    }

    /// Map detector rects into overlay space, keep the vertical bar-like ones
    /// inside the frame, sort left-to-right, and suppress duplicates.
    private func barCandidates(from raw: [NormalizedRect], bufferSize: CGSize) -> [NormalizedRect] {
        var mapped: [NormalizedRect] = []
        for r in raw {
            let o = CropMapper.overlayRect(bufferNormalized: r, bufferSize: bufferSize, viewSize: overlaySize)
            if isBarLike(o) { mapped.append(o) }
        }
        mapped.sort { centerX($0) < centerX($1) }

        // Non-max suppression on centre-x: one physical bar can yield several
        // overlapping rectangles; keep the largest of any cluster.
        var kept: [NormalizedRect] = []
        for c in mapped {
            if let last = kept.last,
               abs(centerX(last) - centerX(c)) < max(c.w, last.w) * 0.6 {
                if area(c) > area(last) { kept[kept.count - 1] = c }
                continue
            }
            kept.append(c)
        }
        return kept
    }

    private func centerX(_ r: NormalizedRect) -> Double { r.x + r.w / 2 }
    private func area(_ r: NormalizedRect) -> Double { r.w * r.h }

    /// A plausible bilah mask. Any backend must land inside the frame; the generic
    /// rectangle fallback additionally must look like a vertical bar, to reject the
    /// wooden frame and rope edges. A trained detector is trusted on shape.
    private func isBarLike(_ r: NormalizedRect) -> Bool {
        guard r.w > 0.01, r.h > 0.01,
              r.x > -0.1, r.y > -0.1,
              r.x + r.w < 1.1, r.y + r.h < 1.1 else { return false }
        if KeyDetector.usesTrainedDetector { return true }
        guard r.h > r.w else { return false }
        return r.w < 0.3 && r.h > 0.08 && r.h < 0.95
    }

    private func confirmAlignment() {
        var profile = app.profile
        profile.keys = keys
        app.profile = profile
        app.saveProfile()
        camera.lockFocusAndExposure()
        app.alignmentConfirmed()
    }

    /// Binding to directly access and mutate a key's axis-aligned rect while clearing free corners.
    private func rectBinding(_ index: Int) -> Binding<NormalizedRect> {
        Binding(
            get: { keys[index].rect },
            set: { newRect in
                keys[index].rect = newRect
                keys[index].corners = nil
            }
        )
    }

    /// Bulk tools work on the axis-aligned rect; drop any free-corner shape so the
    /// quad re-derives from the new rect.
    private func clearCorners() { for i in keys.indices { keys[i].corners = nil } }

    // MARK: - Row-level fit controls

    /// Adjust every mask together — the fast path: Reset to an even row, set the
    /// width/height/spacing to match the bars, then fine-tune individuals by drag.
    private var adjustBar: some View {
        HStack(spacing: 14) {
            adjustGroup("Width", { adjustWidth(-0.004) }, { adjustWidth(0.004) })
            adjustGroup("Height", { adjustHeight(-0.008) }, { adjustHeight(0.008) })
            adjustGroup("Spacing", { adjustSpacing(0.97) }, { adjustSpacing(1.03) })
            adjustGroup("Row", { nudgeRow(-0.01) }, { nudgeRow(0.01) })
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(.black.opacity(0.5))
    }

    private func adjustGroup(_ label: String,
                             _ minus: @escaping () -> Void,
                             _ plus: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.sans(10, weight: .semibold)).textCase(.uppercase).tracking(0.5)
                .foregroundStyle(Theme.inkStone)
            adjustButton("minus", minus)
            adjustButton("plus", plus)
        }
    }

    private func adjustButton(_ system: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.sans(11, weight: .semibold))
                .foregroundStyle(Theme.copper)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(Theme.copper.opacity(0.6), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    /// Resize all masks around their own centres.
    private func adjustWidth(_ delta: Double) {
        for i in keys.indices {
            let center = keys[i].rect.x + keys[i].rect.w / 2
            let w = min(0.4, max(0.02, keys[i].rect.w + delta))
            keys[i].rect.w = w
            keys[i].rect.x = center - w / 2
        }
        clearCorners()
    }

    private func adjustHeight(_ delta: Double) {
        for i in keys.indices {
            let center = keys[i].rect.y + keys[i].rect.h / 2
            let h = min(0.95, max(0.05, keys[i].rect.h + delta))
            keys[i].rect.h = h
            keys[i].rect.y = center - h / 2
        }
        clearCorners()
    }

    /// Spread (>1) or tighten (<1) the whole row around its centre.
    private func adjustSpacing(_ factor: Double) {
        guard !keys.isEmpty else { return }
        let centers = keys.map { $0.rect.x + $0.rect.w / 2 }
        let mean = centers.reduce(0, +) / Double(centers.count)
        for i in keys.indices {
            let newCenter = mean + (centers[i] - mean) * factor
            keys[i].rect.x = newCenter - keys[i].rect.w / 2
        }
        clearCorners()
    }

    /// Move the whole row up (−) or down (+).
    private func nudgeRow(_ delta: Double) {
        for i in keys.indices { keys[i].rect.y += delta }
        clearCorners()
    }
}

/// An axis-aligned rectangular bilah mask.
/// Drag the body to move the rectangle; drag any edge handle to adjust its size while
/// keeping edges axis-aligned. The magnifier shows while dragging an edge handle.
private struct RectMask: View {
    @Binding var rect: NormalizedRect
    let viewSize: CGSize
    let label: String
    let isSelected: Bool
    var onSelect: () -> Void = {}
    /// The edge handle being dragged (overlay-normalised), or nil when not.
    var onResizeFocus: (CGPoint?) -> Void = { _ in }

    @State private var moveStartRect: NormalizedRect?
    @State private var resizeStartRect: NormalizedRect?

    private var frameRect: CGRect {
        rect.rect(in: viewSize)
    }

    var body: some View {
        let w = max(10, frameRect.width)
        let h = max(10, frameRect.height)

        ZStack {
            // Main key rectangle shape
            RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                .fill(Color.black.opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                        .strokeBorder(isSelected ? Theme.cream : Theme.terracotta,
                                     lineWidth: isSelected ? Theme.keyOutlineWidth + 1 : Theme.keyOutlineWidth)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                        .strokeBorder(Theme.cream.opacity(0.3), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .gesture(moveGesture)

            Text(label)
                .font(.sans(13, weight: .bold))
                .foregroundStyle(Theme.cream)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.terracotta, in: Capsule())
                .allowsHitTesting(false)

            // 4 Edge Handles: Top (0), Right (1), Bottom (2), Left (3)
            edgeHandle(0, w: w, h: h)
            edgeHandle(1, w: w, h: h)
            edgeHandle(2, w: w, h: h)
            edgeHandle(3, w: w, h: h)
        }
        .frame(width: w, height: h)
        .position(x: frameRect.midX, y: frameRect.midY)
        .shadow(color: .black.opacity(0.5), radius: 2)
    }

    private var moveGesture: some Gesture {
        DragGesture(coordinateSpace: .named("alignSpace"))
            .onChanged { value in
                onSelect()
                if moveStartRect == nil { moveStartRect = rect }
                guard let start = moveStartRect, viewSize.width > 0, viewSize.height > 0 else { return }
                let dx = value.translation.width / viewSize.width
                let dy = value.translation.height / viewSize.height
                let newX = max(-0.1, min(1.0, start.x + dx))
                let newY = max(-0.1, min(1.0, start.y + dy))
                rect = NormalizedRect(x: newX, y: newY, w: start.w, h: start.h)
            }
            .onEnded { _ in moveStartRect = nil }
    }

    @ViewBuilder
    private func edgeHandle(_ i: Int, w: CGFloat, h: CGFloat) -> some View {
        let isHorizontal = (i == 0 || i == 2)
        let handlePos: CGPoint = {
            switch i {
            case 0: return CGPoint(x: w / 2, y: 0)        // Top
            case 1: return CGPoint(x: w, y: h / 2)        // Right
            case 2: return CGPoint(x: w / 2, y: h)        // Bottom
            case 3: return CGPoint(x: 0, y: h / 2)        // Left
            default: return .zero
            }
        }()

        Capsule()
            .fill(Theme.terracotta)
            .overlay(Capsule().strokeBorder(Theme.cream.opacity(0.8), lineWidth: 1.5))
            .frame(width: isHorizontal ? 24 : 8, height: isHorizontal ? 8 : 24)
            .frame(width: 44, height: 44) // Generous touch target
            .contentShape(Rectangle())
            .position(handlePos)
            .highPriorityGesture(edgeGesture(i))
    }

    private func edgeGesture(_ i: Int) -> some Gesture {
        let minSize = 0.02
        return DragGesture(coordinateSpace: .named("alignSpace"))
            .onChanged { value in
                onSelect()
                if resizeStartRect == nil { resizeStartRect = rect }
                guard let s = resizeStartRect, viewSize.width > 0, viewSize.height > 0 else { return }
                let dx = value.translation.width / viewSize.width
                let dy = value.translation.height / viewSize.height

                var focusPoint = CGPoint.zero

                switch i {
                case 0: // Top edge
                    let newY = min(s.y + s.h - minSize, max(0, s.y + dy))
                    let newH = (s.y + s.h) - newY
                    rect = NormalizedRect(x: s.x, y: newY, w: s.w, h: newH)
                    focusPoint = CGPoint(x: s.x + s.w / 2, y: newY)
                case 1: // Right edge
                    let newW = max(minSize, min(1.0 - s.x, s.w + dx))
                    rect = NormalizedRect(x: s.x, y: s.y, w: newW, h: s.h)
                    focusPoint = CGPoint(x: s.x + newW, y: s.y + s.h / 2)
                case 2: // Bottom edge
                    let newH = max(minSize, min(1.0 - s.y, s.h + dy))
                    rect = NormalizedRect(x: s.x, y: s.y, w: s.w, h: newH)
                    focusPoint = CGPoint(x: s.x + s.w / 2, y: s.y + newH)
                case 3: // Left edge
                    let newX = min(s.x + s.w - minSize, max(0, s.x + dx))
                    let newW = (s.x + s.w) - newX
                    rect = NormalizedRect(x: newX, y: s.y, w: newW, h: s.h)
                    focusPoint = CGPoint(x: newX, y: s.y + s.h / 2)
                default:
                    break
                }
                onResizeFocus(focusPoint)
            }
            .onEnded { _ in resizeStartRect = nil; onResizeFocus(nil) }
    }
}

/// A CamScanner-style magnifier: shows a zoomed crop of the live camera around
/// the point being placed, with a crosshair, so masks can be positioned to the
/// pixel. Sampled from the same buffered frame the overlay maps against.
private struct MagnifierLoupe: View {
    let focus: CGPoint          // overlay-normalised (0…1)
    let image: CGImage
    let bufferSize: CGSize
    let viewSize: CGSize
    var zoom: CGFloat = 2.6
    let diameter: CGFloat = 150

    var body: some View {
        ZStack {
            if let cropped {
                Image(decorative: cropped, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
            }
            // Crosshair at the exact placement point.
            Path { p in
                let c = diameter / 2
                p.move(to: CGPoint(x: c - 14, y: c)); p.addLine(to: CGPoint(x: c + 14, y: c))
                p.move(to: CGPoint(x: c, y: c - 14)); p.addLine(to: CGPoint(x: c, y: c + 14))
            }
            .stroke(Theme.copper, lineWidth: 1.5)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.copper, lineWidth: 2))
        .shadow(color: .black.opacity(0.55), radius: 6)
    }

    /// Crop the buffer image to the region under `focus`, sized so it fills the
    /// loupe at `zoom`. Uses the same aspect-fill math as the overlay mapping.
    private var cropped: CGImage? {
        guard bufferSize.width > 0, bufferSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return nil }
        let scale = max(viewSize.width / bufferSize.width,
                        viewSize.height / bufferSize.height)
        let offsetX = (bufferSize.width * scale - viewSize.width) / 2
        let offsetY = (bufferSize.height * scale - viewSize.height) / 2
        let viewX = focus.x * viewSize.width
        let viewY = focus.y * viewSize.height
        let bufX = (viewX + offsetX) / scale
        let bufY = (viewY + offsetY) / scale
        // View span shown in the loupe → buffer pixels.
        let spanBuf = (diameter / zoom) / scale
        let rect = CGRect(x: bufX - spanBuf / 2, y: bufY - spanBuf / 2,
                          width: spanBuf, height: spanBuf)
        return MalletHitClassifier.crop(image, to: rect)
    }
}

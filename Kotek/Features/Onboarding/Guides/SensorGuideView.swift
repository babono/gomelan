//
//  SensorGuideView.swift
//  Kotek
//
//  Explainer content for "Fitting the sensors" (.sensor guide): where a strike
//  controller's sensors go. Opens by itself the first time the controller
//  setup does, and from its help button after that.
//
//  The gangsa is the designers' mockup drawn in code rather than placed as
//  artwork, because the key count is this instrument's own and the sensors
//  move: one leaves the sample beside the caption, flies to each bilah in turn
//  and tucks under it, and the bilah rings to say it still sounds. Everything
//  is a pure function of the clock, as in `GangsaTable`.
//

import SwiftUI

struct SensorGuideView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The mockup's gangsa is 695 x 124; the geometry below is read off it.
    private static let art = CGSize(width: 695, height: 124)
    /// Between the two posts.
    private static let keysSpan: ClosedRange<CGFloat> = 25 ... 669
    private static let keyGap: CGFloat = 6
    private static let keyTop: CGFloat = 16
    private static let keyBottom: CGFloat = 107.5
    private static let keyRadius: CGFloat = 9.7
    /// Room under the gangsa for the sample sensor and the caption.
    private static let captionHeight: CGFloat = 96

    // The redesign's gangsa: gold bilah, lighter at the top as lit from
    // above, on an orange frame. They were the brown mockup's bronze on teak.
    private static let keyLight = Color(hex: 0xE7B142)
    private static let keyShade = Color(hex: 0xC9932E)
    private static let outline = Color(hex: 0x2F2F2F)
    private static let post = Color(hex: 0xB9541F)
    private static let rail = Color(hex: 0xDF6D2F)
    private static let cord = Color(hex: 0x96561A)
    private static let sensorRing = Color(hex: 0xBE8B1C)
    private static let sensorFace = Color(hex: 0xCCCCCC)

    /// One key's turn: fly, tuck under, ring.
    private static let perKey = 1.2
    /// All of them fitted, before the row clears and starts again.
    private static let hold = 1.8

    /// A fresh profile can still be at zero keys; draw a pemade's ten.
    private var keyCount: Int {
        app.profile.keyCount > 0 ? app.profile.keyCount : 10
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
                // Reduce Motion gets the finished row: every key fitted.
                let t = reduceMotion
                    ? Double(keyCount) * Self.perKey
                    : timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    draw(context, size: size, at: t)
                }
            }
            .accessibilityHidden(true)
            .overlay(alignment: .bottomLeading) {
                caption
                    .frame(height: Self.captionHeight)
                    .padding(.leading, sampleCenter(in: geo.size).x + 64)
            }
        }
        .frame(height: 250)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Attach the sensor under each key, and make sure the key still sounds clear.")
                .font(.sans(17, weight: .semibold))
                .foregroundStyle(Theme.cream)
            Text("Then plug each sensor into the controller and switch it on.")
                .font(.sans(13))
                .foregroundStyle(Theme.cream.opacity(0.65))
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 360, alignment: .leading)
    }

    // MARK: - Layout

    private func scale(in size: CGSize) -> CGFloat {
        min(size.width / Self.art.width, (size.height - Self.captionHeight) / Self.art.height)
    }

    private func origin(in size: CGSize) -> CGPoint {
        CGPoint(x: (size.width - Self.art.width * scale(in: size)) / 2, y: 0)
    }

    /// The sample sensor, left of the caption — where the mockup puts it.
    private func sampleCenter(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * 0.36, y: size.height - Self.captionHeight / 2)
    }

    private var keyWidth: CGFloat {
        let span = Self.keysSpan
        return (span.upperBound - span.lowerBound - Self.keyGap * CGFloat(keyCount - 1)) / CGFloat(keyCount)
    }

    private func keyRect(_ i: Int, in size: CGSize) -> CGRect {
        let s = scale(in: size)
        let o = origin(in: size)
        let x = Self.keysSpan.lowerBound + (keyWidth + Self.keyGap) * CGFloat(i)
        return CGRect(
            x: o.x + x * s,
            y: o.y + Self.keyTop * s,
            width: keyWidth * s,
            height: (Self.keyBottom - Self.keyTop) * s
        )
    }

    /// A fitted sensor's radius: well inside the bilah's width.
    private func fittedRadius(in size: CGSize) -> CGFloat {
        min(keyWidth * scale(in: size) * 0.3, 14)
    }

    private static let sampleRadius: CGFloat = 20

    // MARK: - The clock

    /// Where the loop is: the key being fitted (`keyCount` once all are), how
    /// far through its turn, and how faded the row is as it clears.
    private func moment(at t: Double) -> (key: Int, phase: Double, fade: Double) {
        let cycle = Double(keyCount) * Self.perKey + Self.hold
        let p = t.truncatingRemainder(dividingBy: cycle)
        let key = min(Int(p / Self.perKey), keyCount)
        let phase = key < keyCount ? p / Self.perKey - Double(key) : 0
        let left = cycle - p
        return (key, phase, min(1, left / 0.4))
    }

    private static func ease(_ x: Double) -> Double {
        let x = min(1, max(0, x))
        return x * x * (3 - 2 * x)
    }

    // MARK: - Drawing

    private func draw(_ context: GraphicsContext, size: CGSize, at t: Double) {
        let (current, phase, fade) = moment(at: t)
        let s = scale(in: size)
        let o = origin(in: size)
        let r = fittedRadius(in: size)

        drawFrame(context, scale: s, origin: o)

        // Fitted sensors first, so the bilah cover them: they are UNDER the key,
        // and the rim showing below its foot is how you can tell one is there.
        for i in 0 ..< min(current + 1, keyCount) {
            let key = keyRect(i, in: size)
            let landed = CGPoint(x: key.midX, y: key.maxY + r + 3)
            let tucked = CGPoint(x: key.midX, y: key.maxY - r * 0.15)
            if i < current {
                drawSensor(context, at: tucked, radius: r, opacity: fade)
            } else if phase >= 0.5 {
                let y = landed.y + (tucked.y - landed.y) * Self.ease((phase - 0.5) / 0.18)
                drawSensor(context, at: CGPoint(x: landed.x, y: y), radius: r)
            }
        }

        for i in 0 ..< keyCount {
            // The key just fitted rings once: it should still sound clear.
            let ring = i == current && phase > 0.68 ? (phase - 0.68) / 0.32 : nil
            drawKey(context, index: i, rect: keyRect(i, in: size), scale: s, ring: ring)
        }

        drawSample(context, size: size, current: current, phase: phase)

        // The one on its way, over everything.
        if current < keyCount, phase < 0.5 {
            let key = keyRect(current, in: size)
            let from = sampleCenter(in: size)
            let to = CGPoint(x: key.midX, y: key.maxY + r + 3)
            // Bowed: out to the side first, then up, as a hand would carry it.
            let control = CGPoint(x: from.x * 0.25 + to.x * 0.75, y: from.y)
            let u = CGFloat(Self.ease(phase / 0.5))
            let point = CGPoint(
                x: (1 - u) * (1 - u) * from.x + 2 * (1 - u) * u * control.x + u * u * to.x,
                y: (1 - u) * (1 - u) * from.y + 2 * (1 - u) * u * control.y + u * u * to.y
            )
            var lifted = context
            lifted.addFilter(.shadow(color: .black.opacity(0.4), radius: 6, y: 3))
            drawSensor(lifted, at: point, radius: Self.sampleRadius + (r - Self.sampleRadius) * u)
        }
    }

    /// Posts, the rail the bilah rest on, and the cord threaded under them.
    private func drawFrame(_ context: GraphicsContext, scale s: CGFloat, origin o: CGPoint) {
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: o.x + x * s, y: o.y + y * s, width: w * s, height: h * s)
        }
        context.fill(Path(rect(22, 45, 651, 4)), with: .color(Self.rail))
        var cord = Path()
        cord.move(to: CGPoint(x: o.x + 47 * s, y: o.y + 79 * s))
        cord.addLine(to: CGPoint(x: o.x + 648 * s, y: o.y + 79 * s))
        context.stroke(cord, with: .color(Self.cord), style: StrokeStyle(lineWidth: 12.5 * s, lineCap: .round))
        context.fill(Path(rect(17.8, 0, 4.1, 124)), with: .color(Self.post))
        context.fill(Path(rect(673, 0, 4.1, 124)), with: .color(Self.post))
    }

    private func drawKey(_ context: GraphicsContext, index i: Int, rect: CGRect, scale s: CGFloat, ring: Double?) {
        let shape = RoundedRectangle(cornerRadius: Self.keyRadius * s).path(in: rect)
        context.fill(
            shape,
            with: .linearGradient(
                Gradient(colors: [Self.keyLight, Self.keyShade]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: rect.maxY)
            )
        )
        if let ring {
            let swell = sin(.pi * ring)
            context.fill(shape, with: .color(Theme.keyHighlight.opacity(0.55 * swell)))
            // The sound leaving the bar.
            for wave in 0 ..< 2 {
                let q = ring - Double(wave) * 0.25
                guard q > 0 else { continue }
                let grow = CGFloat(q) * 14 * s
                let halo = RoundedRectangle(cornerRadius: Self.keyRadius * s + grow)
                    .path(in: rect.insetBy(dx: -grow, dy: -grow))
                context.stroke(halo, with: .color(Theme.keyHighlight.opacity(0.7 * (1 - q))), lineWidth: 1.5)
            }
        }
        context.stroke(shape, with: .color(Self.outline), lineWidth: max(1, 1.56 * s))
        context.draw(
            Text("\(i + 1)")
                .font(.sans(max(10, 15 * s), weight: .semibold))
                .foregroundStyle(Self.outline.opacity(0.45)),
            at: CGPoint(x: rect.midX, y: rect.midY)
        )
    }

    /// The sensor as you hold it, on a stub of bilah. A new one grows back on
    /// it once the last has left.
    private func drawSample(_ context: GraphicsContext, size: CGSize, current: Int, phase: Double) {
        let c = sampleCenter(in: size)
        let bar = CGRect(x: c.x - 40, y: c.y - 24, width: 80, height: 48)
        let shape = RoundedRectangle(cornerRadius: 8).path(in: bar)
        context.fill(
            shape,
            with: .linearGradient(
                Gradient(colors: [Self.keyLight, Self.keyShade]),
                startPoint: CGPoint(x: bar.midX, y: bar.minY),
                endPoint: CGPoint(x: bar.midX, y: bar.maxY)
            )
        )
        context.stroke(shape, with: .color(Self.outline), lineWidth: 1.5)
        let grown = current < keyCount ? Self.ease((phase - 0.6) / 0.3) : 1
        if grown > 0 {
            drawSensor(context, at: c, radius: Self.sampleRadius * grown)
        }
    }

    private func drawSensor(_ context: GraphicsContext, at p: CGPoint, radius r: CGFloat, opacity: Double = 1) {
        var context = context
        context.opacity = opacity
        context.fill(disc(at: p, radius: r), with: .color(Self.sensorRing))
        context.fill(disc(at: p, radius: r * 0.75), with: .color(Self.sensorFace))
    }

    private func disc(at p: CGPoint, radius r: CGFloat) -> Path {
        Circle().path(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
    }
}

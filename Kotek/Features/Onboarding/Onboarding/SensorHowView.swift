//
//  SensorHowView.swift
//  Kotek
//
//  "How the sensors work", off the last onboarding slide: one strike's
//  journey from the mallet to the phone, and the three steps it tells.
//
//  A port of the website's explainer (kotek-web, `SensorDiagram` and
//  `SensorExplainer`), drawing for drawing and second for second: the same
//  740 x 252 diagram, the same 3.6 s strike, the same CSS keyframes turned
//  into functions of the clock. The website replays its CSS by remounting the
//  diagram on each strike; here the strike is just `t / 3.6`.
//

import SwiftUI

struct SensorHowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            // Reduce Motion gets the end of a strike: the phone has named it.
            let t = reduceMotion ? 3.0 : timeline.date.timeIntervalSinceReferenceDate
            let strike = Int(floor(t / SensorDiagram.strike))
            let at = t - Double(strike) * SensorDiagram.strike
            VStack(alignment: .leading, spacing: 12) {
                SensorDiagram(key: SensorDiagram.order[strike % SensorDiagram.order.count], at: at)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.deep, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityElement()
                    .accessibilityLabel(
                        "A mallet strikes a bilah. The piezo disc under it feels the vibration, and a signal runs along its wire to a controller, which sends it to the phone by Bluetooth."
                    )

                HStack(alignment: .top, spacing: 18) {
                    ForEach(Self.steps.indices, id: \.self) { i in
                        step(i, at: reduceMotion ? 3.0 : at)
                    }
                }
            }
        }
    }

    private static let steps: [(title: LocalizedStringKey, body: LocalizedStringKey)] = [
        ("You strike the bilah", "It vibrates, the same way it always has."),
        ("A piezo disc feels it", "One small disc under each bilah turns that vibration into a signal."),
        ("Bluetooth tells the app", "A controller sends your phone which bilah you hit, and when."),
    ]

    /// When each step's part of the strike runs: the website's `STEP_TIMES`.
    private static let stepTimes: [(at: Double, for: Double)] = [(0, 1.05), (1.05, 0.7), (1.75, 1.85)]

    private func step(_ i: Int, at t: Double) -> some View {
        let window = Self.stepTimes[i]
        // Lit through its part, ramping over 6% each end; dim the rest.
        let p = (t - window.at) / window.for
        let on = p < 0 || p > 1 ? 0 : min(1, min(p, 1 - p) / 0.06)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(i + 1, format: .number).foregroundStyle(Theme.goldText)
                Text(Self.steps[i].title).foregroundStyle(Theme.heading)
            }
            .font(.serif(22))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(Self.steps[i].body)
                .font(.sans(13))
                .foregroundStyle(Theme.description)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(0.45 + 0.55 * on)
    }
}

/// The diagram: six bilah with a disc under each, the wires to the
/// controller, what the disc feels, Bluetooth, and the phone naming the bilah.
private struct SensorDiagram: View {
    let key: Int
    /// Seconds into this strike.
    let at: Double

    static let strike = 3.6
    /// The bilah struck in turn: not in order, as nobody plays in order.
    static let order = [3, 1, 4, 2]

    private static let size = CGSize(width: 740, height: 252)
    private static let bilah = (count: 6, left: 18.0, top: 46.0, width: 56.0, height: 72.0, gap: 8.0)
    private static let discY = bilah.top + bilah.height + 15
    private static let busY = 212.0
    private static let controller = CGRect(x: 436, y: 172, width: 118, height: 66)
    private static let phone = CGRect(x: 628, y: 58, width: 92, height: 180)
    private static let wave = CGRect(x: 442, y: 74, width: 150, height: 28)

    private static func bilahX(_ k: Int) -> Double {
        bilah.left + Double(k) * (bilah.width + bilah.gap)
    }

    private static func centre(_ k: Int) -> Double {
        bilahX(k) + bilah.width / 2
    }

    var body: some View {
        Canvas { ctx, size in draw(ctx, size: size) }
            .aspectRatio(Self.size.width / Self.size.height, contentMode: .fit)
    }

    // The CSS keyframes, as functions of `at`.

    /// 0…1 of the way through an animation `delay` in, `duration` long.
    private func progress(_ delay: Double, _ duration: Double) -> Double? {
        let p = (at - delay) / duration
        return p < 0 || p > 1 ? nil : p
    }

    private func easeInOut(_ p: Double) -> Double {
        p * p * (3 - 2 * p)
    }

    private func easeOut(_ p: Double) -> Double {
        1 - pow(1 - p, 3)
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize) {
        let s = min(size.width / Self.size.width, size.height / Self.size.height)
        let o = CGPoint(x: (size.width - Self.size.width * s) / 2, y: (size.height - Self.size.height * s) / 2)
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: o.x + x * s, y: o.y + y * s)
        }
        func r(_ rect: CGRect) -> CGRect {
            CGRect(origin: p(rect.minX, rect.minY), size: CGSize(width: rect.width * s, height: rect.height * s))
        }
        func text(_ t: Text, _ x: Double, _ y: Double, size: CGFloat, weight: Font.Weight = .semibold,
                  color: Color = Theme.description, anchor: UnitPoint = .bottomLeading)
        {
            ctx.draw(t.font(.sans(size * s, weight: weight)).foregroundStyle(color), at: p(x, y), anchor: anchor)
        }

        let b = Self.bilah
        let x = Self.centre(key)
        func wire(_ k: Int) -> Path {
            var path = Path()
            path.move(to: p(Self.centre(k), Self.discY))
            path.addLine(to: p(Self.centre(k), Self.busY))
            path.addLine(to: p(Self.controller.minX, Self.busY))
            return path
        }

        // The wires, one from each disc.
        for k in 0 ..< b.count {
            ctx.stroke(wire(k), with: .color(Theme.hairline), lineWidth: 1.5 * s)
        }
        // The signal: a short dash running along the struck bilah's wire.
        if let q = progress(1.05, 0.7) {
            let head = 0.14 + q * 1.0
            let dash = wire(key).trimmedPath(from: max(0, head - 0.14), to: min(1, head))
            ctx.stroke(
                dash,
                with: .color(Theme.primary.opacity(q > 0.95 ? (1 - q) / 0.05 : 1)),
                style: StrokeStyle(lineWidth: 3 * s, lineCap: .round)
            )
        }
        text(Text("One piezo disc under each bilah"), b.left, Self.busY + 22, size: 13)

        // The bilah on their rail, a disc under each.
        let railWidth = Self.bilahX(b.count - 1) + b.width + 2
        ctx.fill(Path(roundedRect: r(CGRect(x: 8, y: 74, width: railWidth, height: 16)), cornerRadius: 4 * s),
                 with: .color(Color(hex: 0xDF6D2F)))
        for k in 0 ..< b.count {
            let bar = Path(
                roundedRect: r(CGRect(x: Self.bilahX(k), y: b.top, width: b.width, height: b.height)),
                cornerRadius: 8 * s
            )
            ctx.fill(bar, with: .color(Theme.bilah))
            let disc = Path(ellipseIn: r(CGRect(x: Self.centre(k) - 11, y: Self.discY - 11, width: 22, height: 22)))
            ctx.fill(disc, with: .color(Color(hex: 0xCCCCCC)))
            ctx.stroke(disc, with: .color(Color(hex: 0xBE8B1C)), lineWidth: 3 * s)
        }

        // The strike: the bilah lights, the disc ripples.
        if let q = progress(0.34, 1.1) {
            let light = q < 0.08 ? q / 0.08 : 1 - (q - 0.08) / 0.92
            let bar = Path(
                roundedRect: r(CGRect(x: Self.bilahX(key), y: b.top, width: b.width, height: b.height)),
                cornerRadius: 8 * s
            )
            ctx.fill(bar, with: .color(Theme.keyHighlight.opacity(easeOut(light))))
        }
        for delay in [0.4, 0.58] {
            guard let q = progress(delay, 0.8) else { continue }
            let e = easeOut(q)
            let radius = 14 * (0.5 + 1.9 * e)
            let ring = Path(ellipseIn: r(CGRect(x: x - radius, y: Self.discY - radius, width: radius * 2, height: radius * 2)))
            ctx.stroke(ring, with: .color(Theme.primary.opacity(0.7 * (1 - e))), lineWidth: 2 * s)
        }

        // The mallet: down onto the bilah in the first tenth, back up by a
        // quarter. The website's mallet is the landing's, at 102 x 76.
        let swing: Double = {
            let q = at / Self.strike
            if q < 0.1 { return 16 * (1 - easeInOut(q / 0.1)) }
            if q < 0.24 { return 16 * easeInOut((q - 0.1) / 0.14) }
            return 16
        }()
        let box = CGRect(x: x - 26, y: b.top + 18 - 43, width: 102, height: 76)
        var m = ctx
        let pivot = p(box.minX + box.width * 0.77, box.minY + box.height * 0.95)
        m.translateBy(x: pivot.x, y: pivot.y)
        m.rotate(by: .degrees(swing))
        m.translateBy(x: -pivot.x, y: -pivot.y)
        m.draw(m.resolve(Image("mallet")), in: r(box))

        // What the disc feels: a spike that rings away to nothing, drawn on.
        ctx.fill(Path(roundedRect: r(CGRect(x: Self.wave.minX - 8, y: 30, width: Self.wave.width + 16, height: 92)),
                      cornerRadius: 12 * s), with: .color(Theme.surface))
        text(Text("What the disc feels"), Self.wave.minX, 21, size: 13)
        var base = Path()
        base.move(to: p(Self.wave.minX, Self.wave.minY))
        base.addLine(to: p(Self.wave.maxX, Self.wave.minY))
        ctx.stroke(base, with: .color(Theme.hairline), lineWidth: 1 * s)
        let drawn = at < 0.42 ? 0 : min(1, (at - 0.42) / 0.75)
        if drawn > 0 {
            var wave = Path()
            for i in 0 ... 150 {
                let u = Double(i) / 150
                let y = exp(-u * 5) * sin(u * 58) * Self.wave.height
                let pt = p(Self.wave.minX + u * Self.wave.width, Self.wave.minY - y)
                if i == 0 { wave.move(to: pt) } else { wave.addLine(to: pt) }
            }
            ctx.stroke(wave.trimmedPath(from: 0, to: drawn), with: .color(Theme.primary), lineWidth: 2 * s)
        }

        // The controller.
        let c = Self.controller
        ctx.fill(Path(roundedRect: r(c), cornerRadius: 14 * s), with: .color(Theme.ireng))
        text(Text("Controller"), c.midX, c.midY, size: 15, color: Theme.putih, anchor: .center)

        // Bluetooth, through the air.
        let air = CGPoint(x: c.maxX + 4, y: c.midY)
        for arc in 0 ..< 3 {
            let radius = 16 + Double(arc) * 16
            let lit: Double = {
                guard let q = progress(1.75 + Double(arc) * 0.18, 0.8) else { return 0.15 }
                return 0.15 + 0.85 * easeInOut(q < 0.4 ? q / 0.4 : (1 - q) / 0.6)
            }()
            var path = Path()
            path.addArc(center: p(air.x, air.y), radius: radius * s,
                        startAngle: .degrees(-45), endAngle: .degrees(45), clockwise: false)
            ctx.stroke(path, with: .color(Theme.sangsihVoice.opacity(lit)),
                       style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))
        }
        text(Text("Bluetooth"), c.maxX + 38, Self.size.height, size: 13, anchor: .bottom)

        // The phone: the bilah that was struck, named.
        let ph = Self.phone
        ctx.fill(Path(roundedRect: r(ph), cornerRadius: 15 * s), with: .color(Theme.ireng))
        ctx.fill(Path(roundedRect: r(ph.insetBy(dx: 5, dy: 5)), cornerRadius: 11 * s), with: .color(Theme.putih))
        let named = at < 2.4 ? 0 : min(1, (at - 2.4) / 0.2)
        if named > 0 {
            var hit = ctx
            hit.opacity = named
            hit.draw(Text("Bilah").font(.sans(13 * s, weight: .semibold)).foregroundStyle(Theme.description),
                     at: p(ph.midX, ph.minY + 66), anchor: .bottom)
            hit.draw(Text(key + 1, format: .number).font(.serif(38 * s)).foregroundStyle(Theme.ireng),
                     at: p(ph.midX, ph.minY + 104), anchor: .bottom)
            hit.fill(Path(roundedRect: r(CGRect(x: ph.minX + 22, y: ph.minY + 122, width: ph.width - 44, height: 10)),
                          cornerRadius: 4 * s), with: .color(Theme.gold))
        }
    }
}

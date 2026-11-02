//
//  ControllerKeyRow.swift
//  Kotek
//
//  The key check's row: one tile per bilah, and the arrow that joins two of
//  them when a stroke on one is heard on the other. Shared by the setup
//  screen and its "Checking the sensors" guide, which plays the same row.
//
//  The mix-up used to be a line of text, an outline on the key asked for and
//  a 0.45 s flash on the key heard — gone before you looked, and nothing tied
//  the two together or said what Remap would change. Both keys now stay marked
//  until it is answered, and the arrow names the swap.
//

import SwiftUI

/// One bilah in the key check: which input is on it, whether it has been
/// confirmed, and a flash whenever a stroke lands on it.
struct ControllerKeyTile: View {
    /// The two sides of a mix-up: the key asked for, and the key whose input
    /// answered instead.
    enum MixUp { case hit, heard }

    let key: Int
    let input: Int?
    let level: Double
    let isChecked: Bool
    let isCurrent: Bool
    var mixUp: MixUp?
    var litHit: UUID?
    var onTap: () -> Void = {}

    @State private var glow = 0.0

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Text("\(key + 1)")
                    .font(.serif(26))
                    .foregroundStyle(Theme.cream)
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                        .fill(fill)
                    // Raw vibration on this key's input — the sensor's own view,
                    // whether or not the stroke matched.
                    RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                        .fill(Theme.gold.opacity(0.35))
                        .scaleEffect(x: 1, y: level, anchor: .bottom)
                    RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                        .fill(Theme.cream.opacity(0.7 * glow))
                    if mixUp == .heard {
                        HeardPulse()
                    }
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.symbol(22, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.bottom, 12)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                        .strokeBorder(border, lineWidth: isCurrent || mixUp != nil ? 3 : 1)
                )
                .frame(maxHeight: .infinity)
                Text(caption)
                    .font(.sans(11, weight: .semibold))
                    .foregroundStyle(captionColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.appPlain)
        .opacity(input == nil && !isCurrent && mixUp == nil ? 0.5 : 1)
        .accessibilityLabel(accessibilityText)
        .onChange(of: litHit) { _, id in
            guard id != nil else { return }
            glow = 1
            withAnimation(.easeOut(duration: 0.45)) { glow = 0 }
        }
    }

    private var fill: Color {
        if isChecked { return Theme.ok }
        return Theme.bronze.opacity(input == nil ? 0.08 : 0.2)
    }

    private var border: Color {
        if mixUp != nil { return Theme.wrong }
        if isCurrent { return Theme.cream }
        return Theme.gold.opacity(0.35)
    }

    /// In a mix-up the two keys say which side they are; the input numbers
    /// are on the arrow.
    private var caption: String {
        switch mixUp {
        case .hit: String(localized: "You hit")
        case .heard: String(localized: "Heard here")
        case nil: input.map { String(localized: "Input \($0 + 1)") } ?? String(localized: "No sensor")
        }
    }

    private var captionColor: Color {
        if mixUp != nil { return Theme.wrong }
        return Theme.cream.opacity(input == nil ? 0.4 : 0.7)
    }

    private var accessibilityText: String {
        var parts = [String(localized: "Key \(key + 1)")]
        parts
            .append(input
                .map { String(localized: "input \($0 + 1)") } ?? String(localized: "no sensor, not heard"))
        if isChecked { parts.append(String(localized: "checked")) }
        if isCurrent { parts.append(String(localized: "hit this key now")) }
        if mixUp == .hit { parts.append(String(localized: "you hit this key")) }
        if mixUp == .heard { parts.append(String(localized: "its sensor answered instead")) }
        return parts.joined(separator: ", ")
    }
}

/// The heard key keeps breathing until the mix-up is answered, so it is still
/// there to find after the stroke's flash has gone.
private struct HeardPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
        if reduceMotion {
            shape.fill(Theme.wrong.opacity(0.4))
        } else {
            shape.fill(Theme.wrong)
                .phaseAnimator([0.2, 0.6]) { content, opacity in
                    content.opacity(opacity)
                } animation: { _ in
                    .easeInOut(duration: 0.7)
                }
        }
    }
}

/// Under the row, joining the key hit to the key heard, labelled with the two
/// inputs Remap will swap. Tiles are equal widths `spacing` apart, which is
/// what lets it find their centres without measuring them.
struct SwapArc: View {
    let keys: (Int, Int)
    /// The input on each of `keys` now, in the same order.
    let inputs: (Int, Int)
    let count: Int
    var spacing: CGFloat = 8
    /// How much of it is drawn — the guide draws it in.
    var progress: Double = 1

    var body: some View {
        GeometryReader { geo in
            let w = (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
            let x = { (k: Int) in (w + spacing) * CGFloat(k) + w / 2 }
            let (left, right) = keys.0 < keys.1 ? (keys.0, keys.1) : (keys.1, keys.0)
            let a = x(left), b = x(right), h = geo.size.height
            let floor = h - 12
            ZStack {
                bracket(from: a, to: b, floor: floor)
                    .trim(from: 0, to: progress)
                    .stroke(Theme.wrong, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                arrowhead(at: a).stroke(Theme.wrong, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .opacity(progress)
                arrowhead(at: b).stroke(Theme.wrong, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .opacity(progress)
                label(left: left)
                    .position(x: (a + b) / 2, y: floor)
                    .opacity(progress)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Remap swaps input \(inputs.0 + 1) and input \(inputs.1 + 1)")
    }

    private func bracket(from a: CGFloat, to b: CGFloat, floor: CGFloat) -> Path {
        let r = min(10, (b - a) / 2)
        var p = Path()
        p.move(to: CGPoint(x: a, y: 2))
        p.addLine(to: CGPoint(x: a, y: floor - r))
        p.addQuadCurve(to: CGPoint(x: a + r, y: floor), control: CGPoint(x: a, y: floor))
        p.addLine(to: CGPoint(x: b - r, y: floor))
        p.addQuadCurve(to: CGPoint(x: b, y: floor - r), control: CGPoint(x: b, y: floor))
        p.addLine(to: CGPoint(x: b, y: 2))
        return p
    }

    private func arrowhead(at x: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x - 5, y: 8))
        p.addLine(to: CGPoint(x: x, y: 2))
        p.addLine(to: CGPoint(x: x + 5, y: 8))
        return p
    }

    /// Left to right, as the keys sit.
    private func label(left: Int) -> some View {
        let (l, r) = keys.0 == left ? inputs : (inputs.1, inputs.0)
        return HStack(spacing: 6) {
            Text("Input \(l + 1)")
            Image(systemName: "arrow.left.arrow.right")
            Text("Input \(r + 1)")
        }
        .font(.sans(12, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Theme.wrong, in: Capsule())
        .fixedSize()
    }
}

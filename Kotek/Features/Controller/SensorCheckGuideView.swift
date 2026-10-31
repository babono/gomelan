//
//  SensorCheckGuideView.swift
//  Kotek
//
//  Explainer content for "Checking the sensors" (.sensorCheck guide): the key
//  check, and above all what Remap does. Opens by itself the first time the
//  check does, and from its help button after that.
//
//  It plays the check's own row (`ControllerKeyTile`, `SwapArc`) rather than a
//  drawing of it, so what you learn here is what the screen then shows: key 3
//  is asked for, key 5 answers, the arrow joins them, Remap swaps the inputs,
//  and the rest check out. A pure function of the clock, as `SensorGuideView`.
//

import SwiftUI

struct SensorCheckGuideView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let keys = 6
    /// R Was 10 s: each step came and went before its text could be read.
    /// Now every step holds for long enough to read it while it plays.
    private static let cycle = 19.0
    /// Reduce Motion gets the frame that explains the most: the mix-up, arrow drawn.
    private static let still = 7.0

    private static let steps: [LocalizedStringResource] = [
        "Hit each key when it's asked for. Its sensor answers and the key gets a tick.",
        "If another key answers instead, the two sensors are in each other's inputs. The arrow joins them.",
        "Remap swaps the two. Hit the wrong bilah by mistake? Choose Try again."
    ]

    var body: some View {
        // One clock for both, so the lit step can never drift from the demo.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion
                ? Self.still
                : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.cycle)
            let demo = Demo(at: t)
            HStack(alignment: .top, spacing: 28) {
                VStack(spacing: 10) {
                    promptRow(demo)
                    row(demo)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity)

                StepList(steps: Self.steps, active: reduceMotion ? nil : demo.step)
                    .frame(width: 270)
            }
        }
        .frame(height: 240)
    }

    private func promptRow(_ demo: Demo) -> some View {
        HStack(spacing: 10) {
            Text(demo.prompt)
                .font(.serif(24))
                .foregroundStyle(promptColor(demo))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if demo.mixUp != nil {
                AppButton(
                    title: "Remap",
                    systemImage: "arrow.left.arrow.right",
                    prominence: .primary,
                    size: .compact
                ) {}
                    .scaleEffect(demo.pressed ? 0.9 : 1)
                    .brightness(demo.pressed ? 0.15 : 0)
            }
        }
        .frame(height: 44)
    }

    private func promptColor(_ demo: Demo) -> Color {
        if demo.mixUp != nil { return Theme.wrong }
        return demo.current == nil ? Theme.hit : Theme.cream
    }

    private func row(_ demo: Demo) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0 ..< Self.keys, id: \.self) { k in
                    ControllerKeyTile(
                        key: k,
                        input: demo.inputs[k],
                        level: demo.levels[k],
                        isChecked: demo.checked.contains(k),
                        isCurrent: demo.current == k,
                        mixUp: demo.mixUp.flatMap { k == $0.hit ? .hit : k == $0.heard ? .heard : nil }
                    )
                    .overlay { strike(on: k, demo) }
                }
            }
            .frame(maxHeight: .infinity)
            if let m = demo.mixUp {
                SwapArc(keys: (m.hit, m.heard), inputs: (2, 4), count: Self.keys, spacing: 6, progress: m.drawn)
                    .frame(height: 36)
                    .padding(.top, 4)
            } else {
                Color.clear.frame(height: 40)
            }
        }
    }

    /// Where the mallet lands: a ring opening out from the key.
    @ViewBuilder
    private func strike(on k: Int, _ demo: Demo) -> some View {
        if let s = demo.strike, s.key == k {
            Circle()
                .stroke(Theme.cream, lineWidth: 3)
                .frame(width: 24, height: 24)
                .scaleEffect(1 + 1.5 * s.age)
                .opacity(1 - s.age)
        }
    }
}

// MARK: - The script

/// Everything on screen at one moment of the loop. Key 3's sensor is in input
/// 5 and key 5's in input 3; keys 1 and 2 are already checked.
private struct Demo {
    var inputs: [Int?] = [0, 1, 2, 3, 4, 5]
    var checked: Set<Int> = [0, 1]
    var current: Int? = 2
    var mixUp: (hit: Int, heard: Int, drawn: Double)?
    var levels = [Double](repeating: 0, count: 6)
    var strike: (key: Int, age: Double)?
    var pressed = false
    var prompt = String(localized: "Hit key 3")
    /// The step the list lights.
    var step = 0

    /// Strokes: when, which key is hit, and which key's input answers. Only
    /// the beats between them are slow — a stroke itself stays a stroke.
    private static let strokes: [(at: Double, key: Int, answers: Int)] = [
        (2.5, 2, 4), (12.0, 3, 3), (13.6, 4, 4), (15.2, 5, 5)
    ]
    /// "Another key answered" is read from here…
    private static let mixUpAt = 2.65
    /// …"Remap swaps the two" from here, with the arrow already drawn…
    private static let explainAt = 6.5
    private static let pressAt = 8.6
    private static let remapAt = 9.0
    /// …and it stays lit a while after, so the swapped inputs are seen.
    private static let swappedUntil = 11.5

    init(at t: Double) {
        for s in Self.strokes where t >= s.at {
            let age = t - s.at
            if age < 0.6 { strike = (s.key, age / 0.6) }
            levels[s.answers] = max(levels[s.answers], exp(-age / 0.25))
        }

        if t >= Self.mixUpAt, t < Self.remapAt {
            let drawn = min(1, (t - Self.mixUpAt) / 0.6)
            mixUp = (2, 4, drawn * drawn * (3 - 2 * drawn))
            prompt = String(localized: "Key 3 was heard on key 5")
            pressed = t > Self.pressAt && t < Self.pressAt + 0.3
            step = t < Self.explainAt ? 1 : 2
        }
        guard t >= Self.remapAt else { return }

        // Remapped: key 3 takes input 5, key 5 takes input 3.
        inputs[2] = 4
        inputs[4] = 2
        checked.insert(2)
        current = 3
        step = t < Self.swappedUntil ? 2 : 0
        for s in Self.strokes.dropFirst() where t >= s.at + 0.15 {
            checked.insert(s.key)
            current = s.key + 1 < 6 ? s.key + 1 : nil
        }
        prompt = current.map { String(localized: "Hit key \($0 + 1)") } ?? String(localized: "All keys check out")
    }
}

// MARK: - Steps

/// The three steps, the one the demo is on lit; nil lights them all.
private struct StepList: View {
    let steps: [LocalizedStringResource]
    let active: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(steps.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.sans(13, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 22, height: 22)
                        .background(Theme.gold, in: Circle())
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 6 }
                    Text(steps[i])
                        .font(.sans(14))
                        .foregroundStyle(Theme.cream)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(active == nil || active == i ? 1 : 0.45)
                .animation(.easeInOut(duration: 0.25), value: active)
            }
            Text("A key with no sensor? Choose “No sensor on key …” and it uses the camera and microphone instead.")
                .font(.sans(12))
                .foregroundStyle(Theme.cream.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

//
//  FreePlayTour.swift
//  Kotek
//
//  The first time you reach free play, Kipli walks you round it: the cycle
//  count, the gangsa, the strike controller (when there is one), voice
//  commands, and the tap that pauses. One stop at a time, the thing he is
//  talking about cut out of a dim and ringed in gold, his bubble beside it
//  with the dots, Skip and Next under it. The clock is held for the whole
//  tour. Free play's pause screen has "Show the tour" to see it again.
//
//  Its stops are spotlights on the real controls (`tourTarget`), not a
//  carousel of pictures of them: a picture of the screen goes stale the
//  first time the screen changes, and does not show where the thing is.
//

import SwiftUI

enum FreePlayTour {
    enum Stop: CaseIterable {
        case cycle, gangsa, sensor, voice, pause

        /// What Kipli says at this stop.
        var line: LocalizedStringResource {
            switch self {
            case .cycle: "This counts your cycles. One cycle is the whole pattern, once round."
            case .gangsa: "Strike each bilah as its note lands on the rail."
            case .sensor: "Sensor on: I can feel every hit, so your results can show the details."
            case .voice: "Hands busy? Turn on voice commands when paused, then say “slower”, “faster” or “pause”."
            case .pause: "Need a break? Tap anywhere to pause. Tempo, your half and this tour are there."
            }
        }

        /// What is lit at this stop, if it is on screen.
        var target: Target {
            switch self {
            case .cycle: .cycle
            case .gangsa: .gangsa
            case .sensor: .sensor
            case .voice: .voice
            case .pause: .stage
            }
        }
    }

    enum Target: Hashable {
        case cycle, sensor, voice, gangsa, stage
    }

    /// The stops for this gangsa: the controller's only when it has one.
    static func stops(hasController: Bool) -> [Stop] {
        Stop.allCases.filter { $0 != .sensor || hasController }
    }

    static let seenKey = "hasSeenFreePlayTour"
}

struct TourTargetKey: PreferenceKey {
    static let defaultValue: [FreePlayTour.Target: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [FreePlayTour.Target: Anchor<CGRect>],
        nextValue: () -> [FreePlayTour.Target: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks what a tour stop lights up.
    func tourTarget(_ target: FreePlayTour.Target) -> some View {
        anchorPreference(key: TourTargetKey.self, value: .bounds) { [target: $0] }
    }
}

/// Over the whole screen while a stop is up: the dim with the target cut out
/// and ringed, and Kipli's card placed off it — below a target in the top
/// half, above one in the bottom, centred on the stage. Swallows every tap,
/// so a tap meant for Next never reaches the screen's tap-to-pause.
struct FreePlayTourOverlay: View {
    let stops: [FreePlayTour.Stop]
    let index: Int
    let targets: [FreePlayTour.Target: Anchor<CGRect>]
    let onNext: () -> Void
    let onSkip: () -> Void

    private var stop: FreePlayTour.Stop {
        stops[index]
    }

    private var isLast: Bool {
        index == stops.count - 1
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let lit = targets[stop.target].map { geo[$0] }
            // The whole stage is lit with a dashed ring inset into it; a
            // control gets breathing room and a solid ring.
            let wide = stop.target == .stage
            let hole = lit.map { wide ? $0.insetBy(dx: 6, dy: 6) : $0.insetBy(dx: -10, dy: -8) }
            let radius: CGFloat = wide ? 18 : 16

            ZStack(alignment: .topLeading) {
                Dim(hole: hole, radius: radius)
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    .contentShape(Rectangle())
                    .onTapGesture {}
                if let hole {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(
                            Theme.gold,
                            style: wide
                                ? StrokeStyle(lineWidth: 2.5, dash: [9, 6])
                                : StrokeStyle(lineWidth: 2.5)
                        )
                        .frame(width: hole.width, height: hole.height)
                        .offset(x: hole.minX, y: hole.minY)
                        .allowsHitTesting(false)
                }
                card
                    .frame(width: cardWidth(in: size))
                    .modifier(Placement(hole: wide ? nil : hole, size: size, cardWidth: cardWidth(in: size)))
            }
            .animation(.easeInOut(duration: 0.3), value: index)
        }
        .transition(.opacity)
    }

    private func cardWidth(in size: CGSize) -> CGFloat {
        min(440, size.width - 32)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            KipliGuide(message: stop.line)
            HStack(spacing: 18) {
                HStack(spacing: 6) {
                    ForEach(stops.indices, id: \.self) { i in
                        Circle()
                            .fill(i == index ? Theme.primary : Theme.hairline)
                            .frame(width: 7, height: 7)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Step \(index + 1) of \(stops.count)")
                Spacer(minLength: 0)
                if !isLast {
                    Button(action: onSkip) {
                        Text("Skip")
                            .font(.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 6)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.appPlain)
                }
                AppButton(
                    title: isLast ? "Let's play" : "Next",
                    prominence: .primary,
                    size: .compact,
                    action: onNext
                )
                .fixedSize()
            }
            // Under the bubble, not the face.
            .padding(.leading, 52 * KipliFace.aspect + 14)
        }
    }
}

/// The dim: the whole screen, and a good way past it into the safe areas,
/// with the lit target's rounded rect cut out of it (even-odd).
private struct Dim: Shape {
    let hole: CGRect?
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path(rect.insetBy(dx: -200, dy: -200))
        if let hole { p.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius)) }
        return p
    }
}

/// Where the card goes for a target: off it vertically, towards the side it
/// is on horizontally, kept 16pt inside the screen. No target — the stage,
/// or a control that is not showing — centres it.
private struct Placement: ViewModifier {
    let hole: CGRect?
    let size: CGSize
    let cardWidth: CGFloat

    func body(content: Content) -> some View {
        if let hole {
            let below = hole.midY < size.height / 2
            let x = hole.midX > size.width / 2 ? hole.maxX - cardWidth : hole.minX
            let clampedX = min(max(16, x), size.width - cardWidth - 16)
            content
                .frame(
                    height: below ? max(0, size.height - hole.maxY - 16) : max(0, hole.minY - 16),
                    alignment: below ? .top : .bottom
                )
                .offset(x: clampedX, y: below ? hole.maxY + 16 : 0)
        } else {
            content
                .frame(width: size.width, height: size.height)
        }
    }
}

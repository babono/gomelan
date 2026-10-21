//
//  ToolRail.swift
//  Kotek
//
//  The piano roll's tools — the four colotomic instruments and the eraser — as
//  a column of icons beside the grid.
//

import SwiftUI

/// Four chips in the controls row were wider than a small phone and slid over
/// the half switcher beside them. A rail costs the grid 52pt of width instead
/// and leaves the row to the half switcher and the snap menu. Picking a half
/// goes back to writing strokes (`PianoRollControls`).
///
/// Icon only, so the names have to come from somewhere without taking width:
/// - TAP arms a tool (tap the armed one again to go back to writing the half).
///   The first tap of each tool also shows its name once, ever (`Defaults`).
/// - HOLD, then slide: the thumb follows the finger from tool to tool, arming
///   each as it passes, with the name of the one under the finger beside it.
///   Letting go keeps the last one.
///
/// One gesture on the whole rail rather than one per icon, because a slide
/// crosses icons and no single icon would see it.
struct ToolRail: View {
    @Bindable var viewModel: CreateKotekViewModel

    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Each icon's frame in the rail's own space, to turn a finger position
    /// into a tool.
    @State private var frames: [Int: CGRect] = [:]
    /// The tool whose name is showing.
    @State private var labelled: Int?
    @State private var scrubbing = false
    /// Moved too far to still be a tap, before the hold made it a slide.
    @State private var wandered = false
    @State private var touching = false
    /// Goes false when the touch ends OR is cancelled by the system (a call, a
    /// system gesture), where `onEnded` would not run and the flags would stick.
    @GestureState private var isDown = false
    @State private var startLocation = CGPoint.zero
    @State private var lastLocation = CGPoint.zero
    @State private var holdTask: Task<Void, Never>?
    @State private var hideTask: Task<Void, Never>?
    /// The slot the slide is over, for the selection haptic.
    @State private var scrubSlot: Int?

    private struct Slot {
        let tool: PianoRollTool
        let name: String
        let accessibilityName: String
        let seenKey: String
        let instrument: ColotomicInstrument?
    }

    private static let slots: [Slot] = ColotomicInstrument.allCases.map {
        Slot(
            tool: .colotomic($0),
            name: $0.title,
            accessibilityName: "Add \($0.title)",
            seenKey: "toolNameSeen.\($0.id)",
            instrument: $0
        )
    } + [Slot(tool: .erase, name: "Erase", accessibilityName: "Delete", seenKey: "toolNameSeen.erase", instrument: nil)]

    /// How long a touch has to stay down before it is a slide, not a tap.
    private static let holdDelay = Duration.milliseconds(350)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< Self.slots.count - 1, id: \.self) { item($0) }

            Rectangle()
                .fill(Theme.cream.opacity(0.15))
                .frame(width: 20, height: 1)
                .padding(.vertical, 2)

            item(Self.slots.count - 1)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .glassEffect(.regular.tint(Theme.glassTint), in: RoundedRectangle(cornerRadius: 26))
        .coordinateSpace(name: "rail")
        .contentShape(Rectangle())
        .gesture(touch)
        .onChange(of: isDown) { _, down in
            guard !down else { return }
            holdTask?.cancel()
            touching = false
            wandered = false
            if scrubbing { endScrub() }
        }
        .overlay(alignment: .topLeading) {
            if let labelled, let frame = frames[labelled] {
                ToolNameBubble(name: Self.slots[labelled].name)
                    // Past the rail's edge, over the grid, level with the icon.
                    .offset(x: frame.maxX + 10, y: frame.midY - 15)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: viewModel.tool)
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: labelled)
        .sensoryFeedback(.selection, trigger: scrubSlot)
        // Above the grid, which is its neighbour and would otherwise cover the
        // name bubble where it overhangs.
        .zIndex(1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tools")
    }

    private func item(_ index: Int) -> some View {
        let slot = Self.slots[index]
        return ToolRailItem(
            accessibilityName: slot.accessibilityName,
            selected: viewModel.tool == slot.tool,
            thumb: thumb,
            onActivate: { toggle(index) }
        ) {
            if let instrument = slot.instrument {
                ColotomicMark(instrument: instrument, scale: 0.9)
            } else {
                Image(systemName: "eraser")
                    .font(.symbol(15, weight: .semibold))
                    .foregroundStyle(Theme.cream)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("rail")) } action: { frames[index] = $0 }
    }

    // MARK: Touch

    private var touch: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("rail"))
            .updating($isDown) { _, down, _ in down = true }
            .onChanged { value in
                lastLocation = value.location
                if !touching {
                    touching = true
                    startLocation = value.startLocation
                    holdTask = Task {
                        try? await Task.sleep(for: Self.holdDelay)
                        if !Task.isCancelled, !wandered { beginScrub() }
                    }
                }
                if scrubbing {
                    scrub(to: value.location)
                } else if hypot(value.location.x - startLocation.x, value.location.y - startLocation.y) > 12 {
                    wandered = true
                    holdTask?.cancel()
                }
            }
            .onEnded { value in
                holdTask?.cancel()
                if scrubbing {
                    endScrub()
                } else if !wandered, let index = slot(at: value.location) {
                    tap(index)
                }
                touching = false
                wandered = false
            }
    }

    private func beginScrub() {
        scrubbing = true
        hideTask?.cancel()
        scrub(to: lastLocation)
    }

    /// The thumb follows the finger, arming each tool it passes over.
    private func scrub(to location: CGPoint) {
        guard let index = nearestSlot(toY: location.y), index != scrubSlot else { return }
        scrubSlot = index
        viewModel.tool = Self.slots[index].tool
        labelled = index
    }

    private func endScrub() {
        scrubbing = false
        scrubSlot = nil
        labelled = nil
    }

    private func tap(_ index: Int) {
        KajarTick.strike()
        toggle(index)
        let key = Self.slots[index].seenKey
        guard !Defaults.bool(key, false) else { return }
        Defaults.set(key, true)
        reveal(index, for: 1.6)
    }

    /// Tapping the armed tool again goes back to writing the half.
    private func toggle(_ index: Int) {
        let tool = Self.slots[index].tool
        viewModel.tool = viewModel.tool == tool ? .notes : tool
    }

    private func reveal(_ index: Int, for seconds: Double) {
        hideTask?.cancel()
        labelled = index
        hideTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { labelled = nil }
        }
    }

    // MARK: Hit testing

    private func slot(at point: CGPoint) -> Int? {
        frames.first { $0.value.insetBy(dx: -4, dy: 0).contains(point) }?.key
    }

    /// Past either end the slide stays on the first or last tool, so the finger
    /// can overshoot the rail without losing it.
    private func nearestSlot(toY y: CGFloat) -> Int? {
        frames.min { abs($0.value.midY - y) < abs($1.value.midY - y) }?.key
    }
}

//
//  WaterfallPlayView.swift
//  Kotek
//
//  Practice without the camera: the gangsa is drawn on screen and the figure
//  falls onto it, Synthesia-style, with a damp cue riding beside every stroke.
//  Strikes come from the piezo sensors (`GangsaSensor`).
//
//  Two views of the same instrument — flat, straight down from above, and
//  tilted towards the player for depth. Swipe up on the gangsa to flip
//  between them (down also flattens it, because that is where a hand goes to
//  undo an upward swipe).
//

import SwiftUI

struct WaterfallPlayView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        WaterfallContentView(app: app)
    }
}

private struct WaterfallContentView: View {
    let app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm: WaterfallPlayViewModel

    init(app: AppState) {
        self.app = app
        _vm = State(wrappedValue: WaterfallPlayViewModel(app: app))
    }

    var body: some View {
        @Bindable var bindableApp = app

        VStack(spacing: 0) {
            topBar(tempo: $bindableApp.tempoScale)

            GeometryReader { geo in
                // The instrument is sized from its HEIGHT and the lane width
                // follows from a bronze bar's own proportions (`GangsaLayout`),
                // so the gangsa keeps its shape on every phone instead of
                // stretching to fill the width. The frame scales with the bars,
                // so its length follows the key count.
                //
                // More than half of it hangs off the bottom of the screen. The near
                // ends of the bars carry nothing — notes land on the top edge —
                // so sinking them buys waterfall height without making the
                // bars any smaller.
                let gangsaHeight = min(150, geo.size.height * 0.44)
                let sunk = gangsaHeight * Self.sunkFraction
                let layout = GangsaLayout(
                    keyCount: vm.keyCount,
                    width: GangsaLayout.width(
                        keyCount: vm.keyCount,
                        height: gangsaHeight,
                        fitting: geo.size.width - 40
                    )
                )
                let lanesWidth = layout.width

                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        WaterfallCanvas(
                            engine: vm.engine,
                            layout: layout,
                            voiced: vm.voicedKeys,
                            yourHalf: app.chosenHalf
                        )
                        StartCaption(engine: vm.engine)
                            .padding(.top, 18)
                    }
                    .frame(width: lanesWidth)
                    .frame(maxHeight: .infinity)

                    GangsaStage(
                        engine: vm.engine,
                        layout: layout,
                        tilted: vm.tilted,
                        sensedStrike: vm.sensedStrike
                    )
                    .frame(width: layout.frameWidth, height: gangsaHeight)
                    .contentShape(Rectangle())
                    .gesture(swipeToTilt)
                    .accessibilityElement()
                    .accessibilityLabel(vm.tilted ? "Gangsa, tilted view" : "Gangsa, flat view")
                    .accessibilityHint("Swipe up to change the view")
                    .accessibilityAction(named: vm.tilted ? "Flat view" : "Tilted view") {
                        toggleTilt()
                    }
                    .padding(.bottom, -sunk)
                }
                .frame(maxWidth: .infinity)
                // The hint can no longer sit under the gangsa — that is off the
                // screen now — so it sits in the empty corner just above it,
                // clear of the frame in both views (the tilt widens the frame).
                .overlay(alignment: .bottomTrailing) {
                    Label(
                        vm.tilted ? "Swipe up for flat" : "Swipe up to tilt",
                        systemImage: "chevron.up"
                    )
                    .font(.sans(11, weight: .medium))
                    .foregroundStyle(Theme.cream.opacity(0.35))
                    .padding(.trailing, 24)
                    .padding(.bottom, gangsaHeight - sunk + layout.postRise + 10)
                }
            }
            // Down to the physical edge of the screen, so "sunk" is measured
            // from the glass and not from the home indicator's inset.
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .background(Theme.ground.ignoresSafeArea())
        .overlay {
            if vm.paused {
                WaterfallPauseOverlay(onResume: vm.resume, onEnd: vm.end, onLeave: vm.leave)
            }
        }
        .onAppear(perform: vm.setup)
        .onDisappear(perform: vm.teardown)
        .onChange(of: app.chosenHalf) { _, _ in vm.halfChanged() }
        .onChange(of: app.tempoScale) { _, new in vm.tempoChanged(new) }
        .onChange(of: app.partnerAudible) { _, new in vm.engine.partnerAudible = new }
        .onChange(of: app.yourVoiceAudible) { _, new in vm.engine.yourVoiceAudible = new }
        .onChange(of: scenePhase) { _, phase in vm.handleScenePhase(phase) }
    }

    // MARK: - Chrome

    private func topBar(tempo: Binding<Double>) -> some View {
        @Bindable var bindableApp = app
        return HStack(spacing: 12) {
            Button(action: vm.pause) {
                Image(systemName: "pause.fill")
                    .font(.symbol(14, weight: .semibold))
                    .foregroundStyle(Theme.cream)
                    .frame(width: 40, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.cream.opacity(0.45), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.kajar)
            .accessibilityLabel("Pause")

            Text(app.selectedKotekan?.name ?? "")
                .font(.sans(13, weight: .semibold))
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(Theme.copper)
                .lineLimit(1)

            SensorDot(status: vm.sensor.status)

            Spacer()
            SessionCountersView(engine: vm.engine, record: vm.record)
            Spacer()

            HalfSwitch(chosenHalf: app.chosenHalf) { app.setHalf($0) }
                .fixedSize()
            VoicesMenu(guide: $bindableApp.yourVoiceAudible, partner: $bindableApp.partnerAudible)
                .fixedSize()
            TempoPicker(tempoScale: tempo)
                .fixedSize()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    /// How much of the instrument sits below the screen edge.
    private static let sunkFraction: CGFloat = 0.5

    private var swipeToTilt: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dy = value.translation.height
                guard abs(dy) > abs(value.translation.width), abs(dy) > 40 else { return }
                if dy < 0 { toggleTilt() } else if vm.tilted { toggleTilt() }
            }
    }

    private func toggleTilt() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { vm.tilted.toggle() }
    }
}

/// "Get ready…" then 3, 2, 1 — written over the empty waterfall rather than
/// dimming it, because the first pass is already falling in behind it.
struct StartCaption: View {
    let engine: PlayEngine

    var body: some View {
        Group {
            if engine.msUntilFirstNote != nil {
                if let n = engine.countdownNumber {
                    Text("\(n)").font(.serif(64)).id(n).transition(.scale.combined(with: .opacity))
                } else {
                    Text("Get ready…").font(.serif(30))
                }
            }
        }
        .foregroundStyle(Theme.cream)
        .shadow(color: .black.opacity(0.6), radius: 8)
        .animation(.snappy(duration: 0.25), value: engine.countdownNumber)
        .allowsHitTesting(false)
    }
}

private struct SensorDot: View {
    let status: GangsaSensor.Status

    var body: some View {
        let (colour, label): (Color, String) = switch status {
        case .connected: (Theme.hit, "Sensors connected")
        case .scanning, .connecting: (Theme.gold, "Looking for sensors")
        case .off, .unavailable: (Theme.miss, "Sensors unavailable")
        }
        HStack(spacing: 6) {
            Circle().fill(colour).frame(width: 8, height: 8)
            Image(systemName: "sensor.tag.radiowaves.forward")
                .font(.symbol(12))
                .foregroundStyle(Theme.cream.opacity(0.6))
        }
        .accessibilityElement()
        .accessibilityLabel(label)
    }
}

struct WaterfallPauseOverlay: View {
    let onResume: () -> Void
    /// Nil where there is nothing to score, so nothing to end — coop's play-along.
    let onEnd: (() -> Void)?
    let onLeave: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 22) {
                Text("Paused").font(.serif(44)).foregroundStyle(Theme.cream)
                HStack(spacing: 16) {
                    PillButton(title: "Resume", style: .filled, action: onResume)
                    if let onEnd {
                        PillButton(title: "End practice", style: .outlined, tint: Theme.copper, action: onEnd)
                    }
                    PillButton(title: "Leave", style: .outlined, tint: Theme.copper, action: onLeave)
                }
            }
        }
    }
}

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
                let framePad: CGFloat = 22
                // The instrument is sized from its HEIGHT and the lane width
                // follows from a bronze bar's own proportions (`GangsaLayout`),
                // so the gangsa keeps its shape on every phone instead of
                // stretching to fill the width.
                //
                // More than half of it hangs off the bottom of the screen. The near
                // ends of the bars carry nothing — notes land on the top edge —
                // so sinking them buys waterfall height without making the
                // bars any smaller.
                let gangsaHeight = min(150, geo.size.height * 0.44)
                let sunk = gangsaHeight * Self.sunkFraction
                let lane = GangsaLayout.lane(forHeight: gangsaHeight)
                let lanesWidth = min(geo.size.width - framePad * 2 - 40,
                                     lane * CGFloat(vm.keyCount))
                let layout = GangsaLayout(keyCount: vm.keyCount, width: lanesWidth)

                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        WaterfallCanvas(engine: vm.engine, layout: layout,
                                        voiced: vm.voicedKeys, yourHalf: app.chosenHalf)
                        StartCaption(engine: vm.engine)
                            .padding(.top, 18)
                    }
                    .frame(width: lanesWidth)
                    .frame(maxHeight: .infinity)

                    GangsaStage(vm: vm, layout: layout, framePad: framePad)
                        .frame(width: lanesWidth + framePad * 2, height: gangsaHeight)
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
                    Label(vm.tilted ? "Swipe up for flat" : "Swipe up to tilt",
                          systemImage: "chevron.up")
                        .font(.sans(11, weight: .medium))
                        .foregroundStyle(Theme.cream.opacity(0.35))
                        .padding(.trailing, 24)
                        .padding(.bottom, gangsaHeight - sunk + 10)
                }
            }
            // Down to the physical edge of the screen, so "sunk" is measured
            // from the glass and not from the home indicator's inset.
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .background(Theme.deep.ignoresSafeArea())
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
        HStack(spacing: 12) {
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

/// The instrument plus what to light on it this frame. Its own view so the
/// per-frame cue rebuild redraws the gangsa and nothing around it.
private struct GangsaStage: View {
    let vm: WaterfallPlayViewModel
    let layout: GangsaLayout
    let framePad: CGFloat

    var body: some View {
        GangsaView(layout: layout, voiced: vm.voicedKeys, cues: cues,
                   tilted: vm.tilted, framePad: framePad)
    }

    private var cues: [Int: BilahCue] {
        let engine = vm.engine
        var cues: [Int: BilahCue] = [:]
        for (key, state) in engine.renderStates {
            cues[key, default: BilahCue()].approach = state.fill
            cues[key, default: BilahCue()].strikeNow = state.strikeNow
            cues[key, default: BilahCue()].hit = state.hit
        }

        // Damp: on in the SAME frame as the strike cue — when the paired stroke
        // is due — and held for the span the engine holds that cue
        // (`tickUserTurnCue`: 55% of the gap to the next stroke, 90…400 ms).
        // "Hit this, pinch that" is one instruction, so it lights as one.
        //
        // It used to fade in a full beat early and out over 0.6 of one after,
        // peaking at the due instant. With strokes a slot apart that window
        // reached back to the previous stroke, so the red was always already
        // up before the strike cue appeared, slid onto the next bar early, lit
        // during rests, and could turn a bar red while it was still the one to
        // strike. The falling cue already gives the warning; the bar only has
        // to say "now".
        //
        // Unlike the strike cue it does not vanish when you hit: the moment
        // after the stroke is exactly when the left hand is pinching.
        let beat = engine.beatLengthMs
        if beat > 0 {
            let yours = engine.fallingNotes(aheadMs: beat * 4, behindMs: 400)
                .filter { $0.voice == .yours }
                .sorted { $0.msAhead < $1.msAhead }
            if let i = yours.lastIndex(where: { $0.msAhead <= 0 }),
               let key = yours[i].dampKey {
                let gap = i + 1 < yours.count ? yours[i + 1].msAhead - yours[i].msAhead : beat
                let hold = min(max(gap * 0.55, 90), 400)
                if -yours[i].msAhead < hold {
                    cues[key, default: BilahCue()].damp = 1
                }
            }
        }

        // The raw sensor, before any judging — so a dead piezo is obvious.
        if let hit = vm.sensor.hits.first, engine.renderNow - hit.hostTime < 0.2 {
            cues[vm.key(forBar: hit.bar), default: BilahCue()].sensed = true
        }
        return cues
    }
}

/// "Get ready…" then 3, 2, 1 — written over the empty waterfall rather than
/// dimming it, because the first pass is already falling in behind it.
private struct StartCaption: View {
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

private struct WaterfallPauseOverlay: View {
    let onResume: () -> Void
    let onEnd: () -> Void
    let onLeave: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 22) {
                Text("Paused").font(.serif(44)).foregroundStyle(Theme.cream)
                HStack(spacing: 16) {
                    PillButton(title: "Resume", style: .filled, action: onResume)
                    PillButton(title: "End practice", style: .outlined, tint: Theme.copper, action: onEnd)
                    PillButton(title: "Leave", style: .outlined, tint: Theme.copper, action: onLeave)
                }
            }
        }
    }
}

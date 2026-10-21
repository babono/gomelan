//
//  WaterfallPlayView.swift
//  Kotek
//
//  Practice without the camera: the gangsa is drawn on screen and the figure
//  falls onto it, Synthesia-style, with a damp cue riding beside every stroke.
//  Strikes come from this gangsa's piezo sensors (`GangsaSensor`), when it
//  has a controller; without one the figure plays and nothing is scored.
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
            // One fixed height for both states. The paused panel is taller
            // than the playing title, and when the bar grew the stage under
            // it shrank — the whole gangsa visibly resized on every pause.
            topBar(tempo: $bindableApp.tempoScale)
                .frame(height: 50)
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
                // The pause dim's top half, behind the paused controls, so
                // together with `PauseStage` it covers the whole screen. It
                // stopped at the top bar, which left a bright band across the
                // top of a paused screen.
                .frame(maxWidth: .infinity)
                .background {
                    if vm.paused {
                        Color.black.opacity(PauseStage.dim).ignoresSafeArea(edges: [.top, .horizontal])
                    }
                }

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
                            yourHalf: app.chosenHalf,
                            damp: app.dampGuide
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
                        sensedStrike: vm.sensedStrike,
                        damp: app.dampGuide,
                        autoStrikes: !vm.sensing
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
                    TiltHint(engine: vm.engine, tilted: vm.tilted)
                        .padding(.trailing, 24)
                        .padding(.bottom, gangsaHeight - sunk + layout.postRise + 10)
                }
            }
            // Down to the physical edge of the screen, so "sunk" is measured
            // from the glass and not from the home indicator's inset.
            .ignoresSafeArea(.container, edges: .bottom)
            // Over the stage only: the session controls are in the top bar
            // while paused, and they have to stay reachable.
            .overlay {
                if vm.paused {
                    PauseStage(
                        resumeCount: vm.resumeCount,
                        onResume: vm.resume,
                        onQuit: vm.end
                    )
                }
            }
        }
        .background(Theme.ground.ignoresSafeArea())
        // A tap anywhere pauses. The pause button it replaces was a 40pt target
        // in a corner, hard to find mid-figure with a panggul in each hand.
        .contentShape(Rectangle())
        .onTapGesture(perform: vm.pause)
        .accessibilityAction(named: "Pause", vm.pause)
        .animation(.easeInOut(duration: 0.2), value: vm.paused)
        .animation(.easeInOut(duration: 0.2), value: vm.resumeCount == nil)
        .onAppear(perform: vm.setup)
        .onDisappear(perform: vm.teardown)
        .onChange(of: app.chosenHalf) { _, _ in vm.halfChanged() }
        .onChange(of: app.tempoScale) { _, new in vm.tempoChanged(new) }
        .onChange(of: app.partnerAudible) { _, new in vm.engine.partnerAudible = new }
        .onChange(of: app.yourVoiceAudible) { _, new in vm.engine.yourVoiceAudible = new }
        .onChange(of: scenePhase) { _, phase in vm.handleScenePhase(phase) }
        .onChange(of: vm.sensing) { _, on in vm.sensingChanged(on) }
    }

    // MARK: - Chrome

    /// Playing: the figure's name and the cycle, nothing else — every control
    /// moved to the pause screen, so there is nothing up here to reach for
    /// mid-figure. Paused: the controls, in one panel around the same title.
    @ViewBuilder
    private func topBar(tempo: Binding<Double>) -> some View {
        @Bindable var bindableApp = app
        if vm.paused, vm.resumeCount == nil {
            HStack(spacing: 14) {
                AppSwitcher(
                    options: [KotekanHalf.polos, .sangsih],
                    selection: app.chosenHalf,
                    title: \.title
                ) { app.setHalf($0) }
                    .fixedSize()
                SessionTitle(name: app.selectedKotekan?.name ?? "", engine: vm.engine, showsScore: vm.sensing)
                sensorDot
                VoiceMixer(
                    yourHalf: app.chosenHalf,
                    yourVoiceAudible: $bindableApp.yourVoiceAudible,
                    partnerAudible: $bindableApp.partnerAudible
                )
                .fixedSize()
                AppMenuPicker<Double>.tempo(tempo)
                    .fixedSize()
                AppMenuPicker(
                    options: DampGuide.allCases,
                    selection: $bindableApp.dampGuide,
                    title: \.title,
                    label: "Damping guide",
                    systemImage: "hand.raised"
                )
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.deep.opacity(0.92), in: RoundedRectangle(cornerRadius: Theme.radius))
            .transition(.opacity)
        } else {
            HStack(spacing: 10) {
                SessionTitle(name: app.selectedKotekan?.name ?? "", engine: vm.engine, showsScore: false)
                sensorDot
            }
            .frame(minHeight: 34)
            .transition(.opacity)
        }
    }

    /// Only a gangsa with a controller has sensors to report on.
    @ViewBuilder
    private var sensorDot: some View {
        if app.profile.controller != nil {
            SensorDot(status: vm.sensor.status)
        }
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

/// "Swipe up to tilt", during the count-in only. It stayed up the whole
/// session and pulled the eye off the falling notes; the count-in is the one
/// stretch with nothing to play, so that is when it gets read.
///
/// Its own view, like `StartCaption`, so reading the clock redraws this label
/// and not the screen around it.
private struct TiltHint: View {
    let engine: PlayEngine
    let tilted: Bool

    var body: some View {
        Group {
            if engine.msUntilFirstNote != nil {
                Label(tilted ? "Swipe up for flat" : "Swipe up to tilt", systemImage: "chevron.up")
                    .font(.sans(11, weight: .medium))
                    .foregroundStyle(Theme.cream.opacity(0.35))
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.4), value: engine.msUntilFirstNote == nil)
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

/// "Ubitan Nyendok - Cycle 12", and on the pause screen " - 86%" after it.
/// Its own view so the cycle ticking over doesn't re-evaluate the screen.
/// Coop's title too.
struct SessionTitle: View {
    let name: String
    let engine: PlayEngine
    let showsScore: Bool

    private var text: String {
        var parts = [name, engine.phase == .countIn ? "Count-in" : "Cycle \(engine.loopIndex + 1)"]
        // Nothing until a pass has scored, rather than a 0% that reads as a verdict.
        if showsScore, engine.judging, let best = engine.bestSoFar {
            parts.append("\(Int((best * 100).rounded()))%")
        }
        return parts.joined(separator: " - ")
    }

    var body: some View {
        Text(text)
            .font(.sans(15, weight: .medium))
            .foregroundStyle(Theme.copper)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.25), value: engine.loopIndex)
    }
}

/// Over the stage while paused: Resume and Quit in glass, or the 3, 2, 1
/// after Resume. The waterfall stays visible behind, dimmed, so you can see
/// where in the figure you will pick up. Coop pauses the same way.
struct PauseStage: View {
    let resumeCount: Int?
    let onResume: () -> Void
    let onQuit: () -> Void

    static let dim = 0.35

    var body: some View {
        ZStack {
            Color.black.opacity(Self.dim).ignoresSafeArea()
            if let n = resumeCount {
                Text("\(n)")
                    .font(.serif(96))
                    .foregroundStyle(Theme.cream)
                    .shadow(color: .black.opacity(0.6), radius: 8)
                    .id(n)
                    .transition(.scale.combined(with: .opacity))
            } else {
                VStack(spacing: 22) {
                    AppIconButton(
                        systemImage: "play.fill",
                        label: "Resume",
                        prominence: .primary,
                        size: .large,
                        action: onResume
                    )
                    AppButton(
                        title: "Quit the session",
                        trailingSystemImage: "rectangle.portrait.and.arrow.right",
                        action: onQuit
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: resumeCount)
    }
}

//
//  CoopPlayView.swift
//  Kotek
//
//  One-screen coop (§6.6.3): two waterfalls side by side, one per player, each
//  a full gangsa in its half's colour. Where both halves strike at the same
//  moment — the unisons the interlock hangs from (§6.6.4) — a band joins the
//  two notes across the gap, brighter when it is the same key.
//
//  The bands are drawn UNDER the lanes, so where one crosses a note it passes
//  behind it: neither player's note is ever covered.
//

import SwiftUI

struct CoopPlayView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        CoopPlayContentView(app: app)
    }
}

private struct CoopPlayContentView: View {
    let app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm: CoopPlayViewModel

    init(app: AppState) {
        self.app = app
        _vm = State(wrappedValue: CoopPlayViewModel(app: app))
    }

    var body: some View {
        @Bindable var bindableApp = app

        // Laid out as the solo waterfall: nothing to reach for while playing
        // — only the title — and a tap anywhere pauses, with every control on
        // the pause screen and a 3, 2, 1 back in.
        VStack(spacing: 0) {
            topBar(tempo: $bindableApp.tempoScale)
                .headerBar()
                .frame(maxWidth: .infinity)
                .background {
                    if vm.paused {
                        Color.black.opacity(PauseStage.dim).ignoresSafeArea(edges: [.top, .horizontal])
                    }
                }
            CoopStage(lanes: vm.lanes, voicedKeys: vm.voicedKeys, damp: app.dampGuide)
                .overlay {
                    if vm.paused {
                        PauseStage(resumeCount: vm.resumeCount, onResume: vm.resume, onQuit: vm.leave)
                    }
                }
        }
        .background(Theme.ground.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture(perform: vm.tapped)
        .accessibilityAction(named: "Pause", vm.pause)
        .animation(.easeInOut(duration: 0.2), value: vm.paused)
        .animation(.easeInOut(duration: 0.2), value: vm.resumeCount == nil)
        .onAppear(perform: vm.setup)
        .onDisappear(perform: vm.teardown)
        .onChange(of: scenePhase) { _, phase in vm.handleScenePhase(phase) }
        .onChange(of: app.tempoScale) { _, new in vm.tempoChanged(new) }
    }

    /// Playing: the figure and the cycle, nothing else. Paused: the session's
    /// controls in one panel around the same title.
    @ViewBuilder
    private func topBar(tempo: Binding<Double>) -> some View {
        @Bindable var bindableApp = app
        let title = SessionTitle(name: vm.kotekan?.name ?? "", engine: vm.clock, showsScore: false)
        if vm.paused, vm.resumeCount == nil {
            HStack(spacing: 14) {
                title
                Text("Play along · not scored")
                    .font(.sans(12))
                    .foregroundStyle(Theme.cream.opacity(0.45))
                    .lineLimit(1)
                AppButton(
                    title: "Guide",
                    systemImage: vm.guideVoices ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    size: .compact
                ) {
                    vm.setGuideVoices(!vm.guideVoices)
                }
                .accessibilityLabel(vm.guideVoices ? "Mute the guide voices" : "Play the guide voices")
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
            title
                .frame(minHeight: 34)
                .transition(.opacity)
        }
    }
}

/// The two lanes side by side, each player's gangsa under their waterfall,
/// the unisons banded across the gap. Coop plays on it; so does Learn's
/// Watch, with the halves for players.
struct CoopStage: View {
    let lanes: [CoopPlayViewModel.Lane]
    let voicedKeys: ClosedRange<Int>
    let damp: DampGuide

    /// The player pill over each lane, for what floats below it (Learn's Kipli).
    static let laneHeader = CoopStageLayout.header

    var body: some View {
        GeometryReader { geo in
            let stage = CoopStageLayout(size: geo.size, keyCounts: lanes.map(\.keyCount))
            ZStack(alignment: .topLeading) {
                UnisonBands(lanes: lanes, stage: stage)
                HStack(alignment: .top, spacing: CoopStageLayout.gap) {
                    ForEach(lanes) { lane in
                        column(lane, stage: stage)
                    }
                }
                .padding(.horizontal, CoopStageLayout.outerPad)
                StartCaption(engine: lanes[0].engine)
                    .frame(width: geo.size.width)
                    .padding(.top, CoopStageLayout.header + 18)
            }
        }
        // Down to the glass, as the solo waterfall does, so the sunk part
        // of each gangsa is measured from the edge of the screen.
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func column(_ lane: CoopPlayViewModel.Lane, stage: CoopStageLayout) -> some View {
        let layout = stage.layout(lane.id)
        return VStack(spacing: 0) {
            LaneHeader(
                player: lane.player,
                gangsa: lanes.allSatisfy { $0.profile.id == lane.profile.id } ? nil : lane.profile.name
            )
            .frame(height: CoopStageLayout.header)
            WaterfallCanvas(
                engine: lane.engine,
                layout: layout,
                voiced: voicedKeys,
                yourHalf: lane.player.half,
                damp: damp,
                autoStrikes: true
            )
            .frame(width: layout.width, height: stage.canvasHeight)
            // Play-along: nothing is sensed, so the bars ring for every stroke.
            GangsaStage(engine: lane.engine, layout: layout, tilted: false, damp: damp, autoStrikes: true)
                .frame(width: layout.frameWidth, height: stage.gangsaHeight)
        }
        // Taller than the stage by the sunk part of the gangsa; aligned to the
        // top, that part hangs off the bottom of the screen.
        .frame(width: stage.columnWidth, height: stage.size.height, alignment: .top)
    }
}

/// Where everything on the stage sits. One struct, read by the lanes and by
/// the bands between them, so a band can never miss the note it joins.
private struct CoopStageLayout {
    let size: CGSize
    let keyCounts: [Int]

    static let outerPad: CGFloat = 20
    /// Wide enough to read as a gap the bands cross, not a seam.
    static let gap: CGFloat = 36
    static let header: CGFloat = 40

    var columnWidth: CGFloat {
        max(0, (size.width - Self.outerPad * 2 - Self.gap) / 2)
    }

    /// No taller than the narrowest lane allows. Each gangsa is narrowed to
    /// fit its column, and at solo's height that left long thin bars: the
    /// hands, which scale with a bar's width, ended partway down them and
    /// floated there instead of reaching off the screen edge as in solo.
    var gangsaHeight: CGFloat {
        let fitted = keyCounts.map { keys in
            GangsaLayout.width(keyCount: keys, height: .greatestFiniteMagnitude, fitting: columnWidth)
                / CGFloat(max(1, keys))
        }
        let byWidth = GangsaLayout.height(forLane: fitted.min() ?? .greatestFiniteMagnitude)
        return min(150, size.height * 0.36, byWidth)
    }

    var canvasHeight: CGFloat {
        // Room for the taller of the two rows of tiles; the rest sinks below
        // the glass, as in solo (`GangsaLayout.shownHeight`).
        let shown = keyCounts.indices.map { layout($0).shownHeight }.max() ?? 0
        return max(0, size.height - Self.header - shown)
    }

    /// Sized from the gangsa's height for a properly proportioned bar, and
    /// narrowed to fit the column — two gangsa side by side rarely have the
    /// room one has alone.
    func layout(_ lane: Int) -> GangsaLayout {
        let keys = keyCounts[lane]
        return GangsaLayout(
            keyCount: keys,
            width: GangsaLayout.width(
                keyCount: keys,
                height: gangsaHeight,
                fitting: columnWidth
            )
        )
    }

    /// The left edge of a lane's waterfall, in stage coordinates.
    func canvasX(_ lane: Int) -> CGFloat {
        let column = Self.outerPad + CGFloat(lane) * (columnWidth + Self.gap)
        return column + (columnWidth - layout(lane).width) / 2
    }
}

private struct LaneHeader: View {
    let player: CoopPlayer
    private static let nameCapHeight = KotekFonts.displayRegular
        .flatMap { UIFont(name: $0, size: 22)?.capHeight } ?? 15
    /// Only when the two players are on different gangsa.
    let gangsa: String?

    var body: some View {
        let colour = player.half == .polos ? Theme.polosVoice : Theme.sangsihVoice
        HStack(spacing: 10) {
            // Learn's Watch has halves, not players: no name, the pill alone.
            if !player.name.isEmpty {
                Text(player.name)
                    .font(.serif(22))
                    .foregroundStyle(Theme.heading)
                    .lineLimit(1)
                    // Neither box nor capitals centre it on the pill: Katibeh's
                    // line box has a deep descent, so box-centred it sat ~5pt
                    // high, and centred on its cap height ~2.5pt low. Cap-centred
                    // plus that measured 2.5pt sits it on the pill's middle.
                    .alignmentGuide(VerticalAlignment.center) { d in
                        d[.firstTextBaseline] - Self.nameCapHeight / 2 + 2.5
                    }
            }
            Text(player.half.title)
                .font(.sans(12, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(colour, in: Capsule())
            if let gangsa {
                Text(gangsa)
                    .font(.sans(12))
                    .foregroundStyle(Theme.cream.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }
}

/// The unisons: a line from one player's note to the other's at the moment
/// both strike.
private struct UnisonBands: View {
    let lanes: [CoopPlayViewModel.Lane]
    let stage: CoopStageLayout

    var body: some View {
        // Read in body so Observation redraws this on the clock — see
        // `WaterfallCanvas.body`.
        let clock = lanes[0].engine
        // swiftlint:disable:next redundant_discardable_let - a bare `_ =` is a () expression in a ViewBuilder
        let _ = clock.currentTimeMs
        Canvas { ctx, _ in
            guard lanes.count == 2 else { return }
            let beatMs = clock.beatLengthMs
            let height = stage.canvasHeight
            guard beatMs > 0, height > 0 else { return }
            let pxPerMs = WaterfallCanvas.pxPerBeat(height: height) / beatMs
            let aheadMs = Double(height) / pxPerMs
            let left = lanes[0].engine.fallingNotes(aheadMs: aheadMs, behindMs: 0).filter { $0.voice == .yours }
            let right = lanes[1].engine.fallingNotes(aheadMs: aheadMs, behindMs: 0).filter { $0.voice == .yours }
            let leftLayout = stage.layout(0), rightLayout = stage.layout(1)

            for a in left {
                // Same clock, same tempo: a unison is the same instant to well
                // under a millisecond. The tolerance is only for float error.
                guard let b = right.first(where: { abs($0.msAhead - a.msAhead) < 1 }) else { continue }
                // Through the middle of the two stroke pills.
                let pill = WaterfallCanvas.strikeHeight(barWidth: leftLayout.barWidth)
                let y = CoopStageLayout.header + height - GangsaLayout.lineInset - a.msAhead * pxPerMs - pill / 2
                guard y > CoopStageLayout.header else { continue }
                let from = stage.canvasX(0) + leftLayout.laneCenter(a.keyIndex) + leftLayout.barWidth / 2
                let to = stage.canvasX(1) + rightLayout.laneCenter(b.keyIndex) - rightLayout.barWidth / 2
                let sameKey = a.keyIndex == b.keyIndex
                var band = Path()
                band.move(to: CGPoint(x: from, y: y))
                band.addLine(to: CGPoint(x: to, y: y))
                ctx.stroke(
                    band,
                    with: .color(sameKey ? Theme.gold.opacity(0.85) : Theme.cream.opacity(0.35)),
                    style: StrokeStyle(lineWidth: sameKey ? 3 : 2, lineCap: .round)
                )
            }
        }
        .frame(width: stage.size.width, height: stage.size.height)
        .allowsHitTesting(false)
    }
}

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

        VStack(spacing: 0) {
            topBar(tempo: $bindableApp.tempoScale)
            GeometryReader { geo in
                let stage = CoopStageLayout(size: geo.size, keyCounts: vm.lanes.map(\.keyCount))
                ZStack(alignment: .topLeading) {
                    UnisonBands(lanes: vm.lanes, stage: stage)
                    HStack(alignment: .top, spacing: CoopStageLayout.gap) {
                        ForEach(vm.lanes) { lane in
                            column(lane, stage: stage)
                        }
                    }
                    .padding(.horizontal, CoopStageLayout.outerPad)
                    StartCaption(engine: vm.clock)
                        .frame(width: geo.size.width)
                        .padding(.top, CoopStageLayout.header + 18)
                }
            }
            // Down to the glass, as the solo waterfall does, so the sunk half
            // of each gangsa is measured from the edge of the screen.
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .background(Theme.ground.ignoresSafeArea())
        .overlay {
            if vm.paused {
                WaterfallPauseOverlay(onResume: vm.resume, onEnd: nil, onLeave: vm.leave)
            }
        }
        .onAppear(perform: vm.setup)
        .onDisappear(perform: vm.teardown)
        .onChange(of: scenePhase) { _, phase in vm.handleScenePhase(phase) }
        .onChange(of: app.tempoScale) { _, new in vm.tempoChanged(new) }
    }

    private func column(_ lane: CoopPlayViewModel.Lane, stage: CoopStageLayout) -> some View {
        let layout = stage.layout(lane.id)
        return VStack(spacing: 0) {
            LaneHeader(
                player: lane.player,
                gangsa: vm.lanes.allSatisfy { $0.profile.id == lane.profile.id } ? nil : lane.profile.name
            )
            .frame(height: CoopStageLayout.header)
            WaterfallCanvas(
                engine: lane.engine,
                layout: layout,
                voiced: vm.voicedKeys,
                yourHalf: lane.player.half
            )
            .frame(width: layout.width, height: stage.canvasHeight)
            GangsaStage(engine: lane.engine, layout: layout, tilted: false)
                .frame(width: layout.frameWidth, height: stage.gangsaHeight)
        }
        // Taller than the stage by the sunk half of the gangsa; aligned to the
        // top, that half hangs off the bottom of the screen.
        .frame(width: stage.columnWidth, height: stage.size.height, alignment: .top)
    }

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

            Text(vm.kotekan?.name ?? "")
                .font(.sans(13, weight: .semibold))
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(Theme.copper)
                .lineLimit(1)

            Spacer()

            Text("Play along · not scored")
                .font(.sans(12))
                .foregroundStyle(Theme.cream.opacity(0.45))

            Button {
                vm.setGuideVoices(!vm.guideVoices)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: vm.guideVoices ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.symbol(12, weight: .semibold))
                    Text("Guide")
                        .font(.sans(12, weight: .semibold))
                }
                .foregroundStyle(vm.guideVoices ? Theme.copper : Theme.cream.opacity(0.5))
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .overlay(Capsule().strokeBorder(Theme.copper.opacity(0.45), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.kajar)
            .accessibilityLabel(vm.guideVoices ? "Mute the guide voices" : "Play the guide voices")

            TempoPicker(tempoScale: tempo)
                .fixedSize()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
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
    /// How much of each gangsa sits below the screen edge, as in solo.
    static let sunkFraction: CGFloat = 0.5

    var columnWidth: CGFloat {
        max(0, (size.width - Self.outerPad * 2 - Self.gap) / 2)
    }

    var gangsaHeight: CGFloat {
        min(150, size.height * 0.36)
    }

    var canvasHeight: CGFloat {
        max(0, size.height - Self.header - gangsaHeight * (1 - Self.sunkFraction))
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
    /// Only when the two players are on different gangsa.
    let gangsa: String?

    var body: some View {
        let colour = player.half == .polos ? Theme.polosVoice : Theme.sangsihVoice
        HStack(spacing: 10) {
            Text(player.name)
                .font(.serif(22))
                .foregroundStyle(Theme.cream)
                .lineLimit(1)
            Text(player.half.title)
                .font(.sans(11, weight: .bold))
                .textCase(.uppercase)
                .tracking(1.4)
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
                // Level with the key number near the foot of each block.
                let y = CoopStageLayout.header + height - a.msAhead * pxPerMs - 11
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

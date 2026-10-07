//
//  SensorPlayView.swift
//  Kotek
//
//  Dev screen: a real practice session driven ONLY by the piezo sensors — no
//  camera, no microphone. Three sensors, three bilah, one three-tone kotekan.
//
//  It runs the same `PlayEngine` as `PlayView`, so the count-in, the partner
//  half, the judgement windows and the score are the real thing; the only
//  difference is where `registerStrike` gets its key and time from. Use it to
//  answer: does the sensor's bar + timestamp alone carry a session, before any
//  work goes into fusing it with vision and audio.
//
//  Ubitan Nyendok, because it is the one figure that fits on three bilah
//  (keys 5…7). Sensor bar 0 sits on the lowest of them.
//

import FactoryKit
import SwiftUI

struct SensorPlayView: View {
    @Environment(AppState.self) private var app
    @State private var viewModel: SensorPlayViewModel

    @MainActor
    init(viewModel: SensorPlayViewModel? = nil) {
        _viewModel = State(wrappedValue: viewModel ?? SensorPlayViewModel())
    }

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            header(vm: vm)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 12) {
                    packetLine(sensor: vm.sensor)
                    SensorBars(engine: vm.engine, sensor: vm.sensor, keys: vm.keys)
                    summary(vm: vm)
                }
                .frame(maxWidth: .infinity)
                hitLog(sensor: vm.sensor).frame(width: 220)
            }
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity)

            NotesRiver(
                engine: vm.engine,
                keyRange: vm.keys,
                keyCount: app.profile.keys.count,
                yourHalf: vm.half
            )
        }
        .background(Theme.ink)
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onChange(of: vm.half) { _, new in
            viewModel.updateHalf(new)
        }
        .onChange(of: vm.tempo) { _, new in
            viewModel.updateTempo(new)
        }
    }

    // MARK: - Chrome

    private func header(vm: SensorPlayViewModel) -> some View {
        @Bindable var bindableVM = vm

        return HStack(spacing: 12) {
            SecondaryButton(title: "Back", systemImage: "chevron.left") {
                app.closeSensorTest()
            }
            statusPill(sensor: vm.sensor)
            Spacer()
            Picker("Half", selection: $bindableVM.half) {
                ForEach([KotekanHalf.polos, .sangsih]) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            Picker("Tempo", selection: $bindableVM.tempo) {
                ForEach(Theme.tempoScales, id: \.self) { Text(Theme.tempoLabel($0)).tag($0) }
            }
            .tint(Theme.gold)
            SecondaryButton(
                title: vm.running ? "Stop" : "Play",
                systemImage: vm.running ? "stop.fill" : "play.fill"
            ) {
                vm.toggleSession(app: app)
            }
        }
    }

    private func statusPill(sensor: GangsaSensor) -> some View {
        let (text, color): (String, Color) = switch sensor.status {
        case .off: ("Off", Theme.stone)
        case .scanning: ("Searching for Gangsa-Sensor…", Theme.gold)
        case .connecting: ("Connecting…", Theme.gold)
        case .connected: ("Sensor connected", Theme.hit)
        case .unavailable(let why): (why, Theme.miss)
        }
        return HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text).font(.sans(12, weight: .semibold)).foregroundStyle(Theme.cream)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.black.opacity(0.35), in: Capsule())
    }

    @ViewBuilder
    private func packetLine(sensor: GangsaSensor) -> some View {
        if sensor.status == .scanning {
            Text(
                sensor.seenDevices.isEmpty
                    ? "scanning · no Bluetooth devices heard yet"
                    : "scanning · heard " + sensor.seenDevices.suffix(12).joined(separator: ", ")
            )
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Theme.gold)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        packetCounts(sensor: sensor)
    }

    private func packetCounts(sensor: GangsaSensor) -> some View {
        Text(
            "packets · events \(sensor.eventPackets) · levels \(sensor.levelPackets)"
                + (sensor.rejectedPackets > 0 ? " · rejected \(sensor.rejectedPackets)" : "")
        )
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(sensor.rejectedPackets > 0 ? Theme.miss : Theme.cream.opacity(0.5))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summary(vm: SensorPlayViewModel) -> some View {
        Group {
            if vm.running {
                SensorSessionLine(engine: vm.engine)
            } else if let r = vm.lastResult {
                Text("Last run · \(r.landedNotes) notes landed")
            } else {
                Text("\(vm.figure.name) on bilah \(vm.keys.lowerBound + 1)–\(vm.keys.upperBound + 1). Press Play, then strike along.")
            }
        }
        .font(.sans(13, weight: .semibold))
        .foregroundStyle(Theme.cream.opacity(0.8))
    }

    private func hitLog(sensor: GangsaSensor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("Hits")
                Spacer()
                Button("Clear") { sensor.clearHits() }
                    .font(.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.gold)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sensor.hits) { h in
                        HStack {
                            Text("bar \(h.bar + 1)")
                            Spacer()
                            Text("\(h.strength)")
                            Text(h.intervalMs.map { "+\($0)ms" } ?? "—")
                                .frame(width: 72, alignment: .trailing)
                        }
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.cream.opacity(0.85))
                    }
                }
            }
        }
        .padding(12)
        .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: Theme.radius))
    }
}

/// One tile per sensor: the live piezo level, the engine's approach fill for
/// that bilah, and the judgement of the last stroke on it. Its own view so the
/// per-frame engine reads invalidate only this.
private struct SensorBars: View {
    let engine: PlayEngine
    let sensor: GangsaSensor
    let keys: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<GangsaSensor.barCount, id: \.self) { bar in
                tile(bar: bar, key: keys.lowerBound + bar)
            }
        }
    }

    private func tile(bar: Int, key: Int) -> some View {
        let state = engine.renderStates[key] ?? KeyRenderState()
        let floater = engine.floaters.last {
            $0.keyIndex == key && engine.renderNow - $0.bornAt < engine.floaterDuration
        }
        let lastHit = sensor.hits.first { $0.bar == bar }

        return VStack(spacing: 8) {
            Text(floater?.label.text ?? " ")
                .font(.sans(13, weight: .black))
                .foregroundStyle(floater.map { color($0.label) } ?? .clear)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                    .fill(Theme.bronze.opacity(0.18))
                // Approach: fills as this bilah's next stroke comes due.
                RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                    .fill(Theme.upcoming.opacity(0.55))
                    .scaleEffect(x: 1, y: state.fill, anchor: .bottom)
                RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                    .strokeBorder(
                        state.strikeNow ? Theme.cream : Theme.gold.opacity(0.4),
                        lineWidth: state.strikeNow ? 4 : 1
                    )
                if state.hit {
                    RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                        .fill(Theme.hit.opacity(0.5))
                }
                HitPulse(hitID: lastHit?.id)
            }
            .frame(maxHeight: .infinity)
            // Raw piezo level from the LEVEL characteristic — the sensor's own
            // view, independent of whether the engine scored anything.
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(Theme.gold).frame(width: g.size.width * sensor.levels[bar])
                }
            }
            .frame(height: 8)
            Text("Sensor \(bar + 1) · bilah \(key + 1)")
                .font(.sans(12, weight: .semibold))
                .foregroundStyle(Theme.cream.opacity(0.7))
            Text("\(sensor.hitCounts[bar]) hits · last \(lastHit.map { "\($0.strength)" } ?? "—")")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.cream.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private func color(_ label: PlayEngine.FloaterLabel) -> Color {
        switch label {
        case .perfect, .goodEarly, .goodLate: Theme.hit
        case .late, .wrongKey: Theme.wrong
        case .miss, .unmatched: Theme.miss
        }
    }
}

/// "The sensor fired", straight from the EVENT packet — before and regardless
/// of the engine, so it works with no session running.
///
/// Animated per hit rather than derived from "is the newest hit < 150 ms
/// old". That version only cleared when something else happened to redraw the
/// tile, so with the LEVEL stream quiet a flash could stick, or never show.
private struct HitPulse: View {
    let hitID: UUID?
    @State private var glow = 0.0

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
            .fill(Theme.cream.opacity(0.75 * glow))
            .overlay {
                Text("HIT")
                    .font(.sans(28, weight: .black))
                    .foregroundStyle(Theme.ink)
                    .opacity(glow)
                    .scaleEffect(0.8 + 0.2 * glow)
            }
            .allowsHitTesting(false)
            .onChange(of: hitID) { _, id in
                guard id != nil else { return }
                glow = 1
                withAnimation(.easeOut(duration: 0.45)) { glow = 0 }
            }
    }
}

private struct SensorSessionLine: View {
    let engine: PlayEngine

    var body: some View {
        if let ms = engine.msUntilFirstNote {
            Text("Count-in · first note in \(Int(ms / 1000) + 1)s")
        } else {
            Text(
                "Cycle \(engine.loopIndex + 1) · \(engine.landedNotes) landed · best \(engine.bestSoFar.map { "\(Int($0 * 100))%" } ?? "—")"
            )
        }
    }
}

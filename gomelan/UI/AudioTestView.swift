//
//  AudioTestView.swift
//  gomelan
//
//  Dev screen for the audio strike TRIGGER (not per-key — the generic onset the
//  vision path snaps its timing onto). Shows every onset the detector surfaces,
//  its loudness against the current amplitude gate, and whether it was accepted.
//
//  Use it to answer: is audio firing on real strikes, is background noise getting
//  through, and is the gate too high (strikes below the line) or too low (noise
//  above it)? Tap the gangsa and watch the bars; the noise floor shows between.
//

import SwiftUI

struct AudioTestView: View {
    @Environment(AppState.self) private var app
    let audio: AudioEngineController

    struct OnsetEvent: Identifiable {
        let id = UUID()
        let amplitude: Float
        let gate: Float
        let passedGate: Bool
        let fingerprinted: Bool
    }

    @State private var history: [OnsetEvent] = []
    @State private var lastEvent: OnsetEvent?
    @State private var onsetCount = 0
    @State private var acceptedCount = 0

    // Live-tunable gate (seeded from the engine on appear).
    @State private var gateFloor: Float = 0.04
    @State private var gateRelative: Float = 0.12

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                header
                statusPanel
                historyStrip
                gateControls
                Text("Tap the gangsa. Green = accepted strike · Yellow = passed gate but no fingerprint · Grey = below gate (too quiet / noise floor).")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
            .padding(.top, 24)
        }
        .onAppear {
            try? audio.start(profile: app.profile)
            let g = audio.gateSettings()
            gateFloor = g.floor
            gateRelative = g.relative
            audio.onOnsetDebug = { d in
                Task { @MainActor in ingest(d) }
            }
        }
        .onDisappear {
            audio.onOnsetDebug = nil
            audio.stop()
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 16) {
            SecondaryButton(title: "Back", systemImage: "chevron.left") { app.closeAudioTest() }
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(audio.isRunning ? Theme.hit : Theme.miss).frame(width: 10, height: 10)
                Text("onsets \(onsetCount) · accepted \(acceptedCount)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.black.opacity(0.5), in: Capsule())
        }
        .padding(.horizontal, 24)
    }

    private var statusPanel: some View {
        VStack(spacing: 16) {
            Text(statusText)
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(statusColor)

            if let e = lastEvent {
                meter(label: "strike", value: e.amplitude, color: .blue)
                meter(label: "gate", value: e.gate, color: Theme.miss)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 24)
    }

    private func meter(label: String, value: Float, color: Color) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 48, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(color)
                        .frame(width: geo.size.width * CGFloat(min(1, value / scale)))
                }
            }
            .frame(height: 14)
            Text(String(format: "%.3f", value))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 24)
    }

    private var historyStrip: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(history) { e in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: e))
                    .frame(width: 6, height: max(2, 120 * CGFloat(min(1, e.amplitude / scale))))
            }
        }
        .frame(height: 120, alignment: .bottom)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 24)
        .overlay(alignment: .leading) {
            // Gate reference line (uses the most recent gate).
            if let g = lastEvent?.gate {
                Rectangle()
                    .fill(Theme.miss.opacity(0.6))
                    .frame(height: 1)
                    .offset(y: 60 - 120 * CGFloat(min(1, g / scale)))
                    .padding(.horizontal, 24)
            }
        }
    }

    private var gateControls: some View {
        VStack(spacing: 12) {
            slider(label: "floor", value: $gateFloor, range: 0.005...0.30)
            slider(label: "relative", value: $gateRelative, range: 0...0.50)
        }
        .padding(.horizontal, 24)
        .onChange(of: gateFloor) { _, _ in pushGate() }
        .onChange(of: gateRelative) { _, _ in pushGate() }
    }

    private func slider(label: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 64, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.3f", value.wrappedValue))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func pushGate() {
        audio.setGate(floor: gateFloor, relative: gateRelative)
    }

    // MARK: - Helpers

    private var scale: Float {
        max(0.02, (history.map { max($0.amplitude, $0.gate) }.max() ?? 0.02))
    }

    private var statusText: String {
        guard let e = lastEvent else { return "LISTENING" }
        if !e.passedGate { return "TOO QUIET" }
        return e.fingerprinted ? "STRIKE" : "STRIKE?"
    }

    private var statusColor: Color {
        guard let e = lastEvent else { return .white.opacity(0.5) }
        if !e.passedGate { return .white.opacity(0.4) }
        return e.fingerprinted ? Theme.hit : Theme.accent
    }

    private func color(for e: OnsetEvent) -> Color {
        if !e.passedGate { return .white.opacity(0.25) }
        return e.fingerprinted ? Theme.hit : Theme.accent
    }

    private func ingest(_ d: AudioEngineController.OnsetDebug) {
        let e = OnsetEvent(amplitude: d.amplitude, gate: d.gate,
                           passedGate: d.passedGate, fingerprinted: d.fingerprinted)
        history.append(e)
        if history.count > 60 { history.removeFirst(history.count - 60) }
        lastEvent = e
        onsetCount += 1
        if d.passedGate { acceptedCount += 1 }
    }
}

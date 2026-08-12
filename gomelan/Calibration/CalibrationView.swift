//
//  CalibrationView.swift
//  gomelan
//
//  Baseline · learn this gamelan's voice.
//
//  Gomelan no longer calibrates each bilah's pitch. It only needs to learn what
//  a real strike on THIS gangsa SOUNDS like — one generic spectral template —
//  so that during play a genuine strike can be told apart from a scream, a clap
//  or a hovering mallet. The learner just listens: strike any key a few times,
//  soft and hard, and a confidence ring fills as clean strikes accumulate.
//
//  Backed by AudioEngineController's baseline API:
//    startBaselineCapture() → onOnsetDebug (per strike) → finishBaselineCapture()
//

import SwiftUI
import QuartzCore

struct CalibrationView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController
    let audio: AudioEngineController

    /// Clean strikes needed to consider the voice learned.
    private let strikesNeeded = 6

    @State private var strikeCount = 0
    /// Whether the most recent strike was folded in or rejected as an outlier.
    @State private var lastAccepted: Bool?
    /// Amplitude + time of the most recent strike, for the mic visualisation.
    @State private var micLevel: Float = 0
    @State private var micLevelTime: Double = 0
    @State private var committing = false

    private var confidence: Double { min(1, Double(strikeCount) / Double(strikesNeeded)) }
    private var learned: Bool { strikeCount >= strikesNeeded }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                CameraPreview(session: camera.session)
                    .overlay(Color.black.opacity(0.35))

                faintMasks

                VStack {
                    Spacer()
                    panel
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .background(Theme.ink)
        .onAppear(perform: setup)
        .onDisappear(perform: teardown)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            SecondaryButton(title: "Cancel", systemImage: "xmark") { cancel() }
            Spacer()
            VStack(spacing: 4) {
                SectionLabel("Baseline · learn this gamelan's voice", color: Theme.copper)
                Text(learned ? "voice learned" : "listening")
                    .font(.sans(13))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Text("\(min(strikeCount, strikesNeeded)) / \(strikesNeeded)")
                .font(.sans(14, weight: .medium))
                .foregroundStyle(Theme.copper)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var faintMasks: some View {
        GeometryReader { geo in
            ForEach(app.profile.keys) { key in
                let f = key.rect.rect(in: geo.size)
                RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                    .strokeBorder(Theme.copper.opacity(0.25), lineWidth: 1.5)
                    .frame(width: f.width, height: f.height)
                    .position(x: f.midX, y: f.midY)
            }
        }
    }

    // MARK: - Panel

    private var panel: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("What the mic hears", color: Theme.inkStone)
                micVisualization.frame(height: 72)
                Text(learned
                     ? "Gomelan now knows this gangsa's strike from a clap or a scream."
                     : "Strike any key — soft, then hard. The first couple seed its voice; sounds unlike them are ignored.")
                    .font(.sans(13))
                    .foregroundStyle(Theme.inkStone)
                    .fixedSize(horizontal: false, vertical: true)
                if let lastAccepted {
                    Label(lastAccepted ? "heard a strike" : "ignored — didn't match the others",
                          systemImage: lastAccepted ? "checkmark.circle" : "xmark.circle")
                        .font(.sans(12, weight: .medium))
                        .foregroundStyle(lastAccepted ? Theme.copper : Theme.inkStone)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(Theme.copper.opacity(0.2)).frame(width: 1, height: 150)

            VStack(spacing: 16) {
                confidenceRing
                HStack(spacing: 14) {
                    PillButton(title: "Reset", style: .outlined, tint: Theme.inkStone) { reset() }
                    PillButton(title: learned ? "Continue" : "Listening…",
                               style: learned ? .filled : .outlined,
                               tint: Theme.copper) {
                        if learned { commit() }
                    }
                    .disabled(!learned || committing)
                    .opacity(learned ? 1 : 0.5)
                }
            }
            .frame(width: 300)
        }
        .padding(24)
        .background(Theme.ink.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
        .padding(20)
    }

    private var confidenceRing: some View {
        ZStack {
            Circle().stroke(Theme.copper.opacity(0.18), lineWidth: 10)
            Circle()
                .trim(from: 0, to: confidence)
                .stroke(Theme.copper, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: confidence)
            VStack(spacing: 2) {
                Text("\(Int((confidence * 100).rounded()))%")
                    .font(.serif(40))
                    .foregroundStyle(Theme.cream)
                    .contentTransition(.numericText())
                SectionLabel("confidence", color: Theme.inkStone)
            }
        }
        .frame(width: 150, height: 150)
    }

    /// A lightweight "spectrum" that pulses on each strike and decays between
    /// them — a felt sense of the mic hearing something, not a real FFT plot.
    private var micVisualization: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            // micLevelTime is CACurrentMediaTime; convert both to a decay age.
            let age = max(0, CACurrentMediaTime() - micLevelTime)
            let level = Double(micLevel) * exp(-age / 0.45)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<22, id: \.self) { i in
                    let profile = Self.spectrumProfile[i % Self.spectrumProfile.count]
                    let jitter = 0.8 + 0.2 * sin(now * 6 + Double(i))
                    let h = max(3, 88 * min(1, level * 3) * profile * jitter)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.copper.opacity(0.85))
                        .frame(width: 6, height: h)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A fixed, roughly gangsa-shaped relative envelope (bright fundamental,
    /// decaying inharmonic partials) so the bars look like a strike, not noise.
    private static let spectrumProfile: [Double] =
        [0.35, 0.9, 0.6, 0.45, 1.0, 0.5, 0.3, 0.7, 0.4, 0.55, 0.25]

    // MARK: - Audio wiring

    private func setup() {
        camera.start()
        try? audio.start(profile: app.profile)
        audio.clearBaseline()
        audio.startBaselineCapture()
        // Pulse the visualisation on any loud onset…
        audio.onOnsetDebug = { debug in
            Task { @MainActor in
                guard debug.passedGate else { return }
                micLevel = debug.amplitude
                micLevelTime = debug.hostTime
            }
        }
        // …but let the engine decide which strikes actually count: it folds in
        // ones that resemble the template so far and rejects outliers.
        audio.onBaselineProgress = { progress in
            Task { @MainActor in
                strikeCount = progress.accepted
                lastAccepted = progress.wasAccepted
            }
        }
    }

    private func reset() {
        strikeCount = 0
        lastAccepted = nil
        audio.startBaselineCapture()   // drops the old accumulator, starts fresh
    }

    private func commit() {
        guard !committing else { return }
        committing = true
        audio.finishBaselineCapture { count, template in
            if let template {
                var updated = app.profile
                updated.strikeBaseline = template
                app.profile = updated
                app.saveProfile()
            }
            app.baselineFinished()
        }
    }

    private func cancel() {
        audio.onOnsetDebug = nil
        audio.onBaselineProgress = nil
        audio.clearBaseline()
        audio.stop()
        app.skipCalibration()
    }

    private func teardown() {
        audio.onOnsetDebug = nil
        audio.onBaselineProgress = nil
        audio.stop()
    }
}

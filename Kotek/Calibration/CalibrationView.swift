//
//  CalibrationView.swift
//  Kotek
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
//  Laid out like 2/4 and 3/4 and for the same reason: full-bleed camera, chrome
//  floating over scrims at the top and bottom. It used to be a letterboxed
//  preview under a bar, with a big translucent card parked in the middle of it —
//  three surfaces where the neighbouring steps have one, and a card sitting over
//  the instrument you are being asked to strike. Whatever the card was holding
//  fits in a single strip, and the strip leaves the gangsa visible.
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
    /// Up from the moment this screen appears until it is actually listening.
    /// Starting the audio engine is not instant, and this screen builds its own
    /// camera preview, which is black until it warms up.
    @State private var preparing = true

    private var confidence: Double { min(1, Double(strikeCount) / Double(strikesNeeded)) }
    private var learned: Bool { strikeCount >= strikesNeeded }

    private var busyMessage: String? {
        if preparing { return "Getting ready to listen…" }
        // Folding the accepted strikes into one template, then writing the
        // profile — short, but it ends in a screen change, so it is shown.
        return committing ? "Learning the strike…" : nil
    }

    var body: some View {
        ZStack {
            CameraPreview(camera: camera)
                .ignoresSafeArea()
                //R The same 0.22 the aligning step settles its feed with, not
                //R the 0.35 this screen used to use: that was dimming a preview
                //R behind a solid card, and there is no card any more.
                .overlay(Color.black.opacity(0.22).ignoresSafeArea())

            faintMasks
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TopBar(title: "Learn this gangsa's voice",
                       backTitle: "Cancel",
                       onBack: { cancel() },
                       trailingText: "4 / 4",
                       tint: Theme.cream, accent: Theme.copper,
                       compact: true)
                    .background(
                        LinearGradient(colors: [.black.opacity(0.5), .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea(edges: [.top, .horizontal])
                    )

                Spacer()

                bottomBar
            }
        }
        .background(Theme.ink)
        .busy(busyMessage)
        .onAppear {
            //R Paint the scrim BEFORE setup runs: starting the audio engine
            //R blocks for a moment, and a spinner that only appears afterwards
            //R has missed the wait it was there for.
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                setup()
                //R Hold while this screen's own camera preview warms up — it
                //R reports nothing when it is ready. See AligningView.
                try? await Task.sleep(for: .milliseconds(900))
                preparing = false
            }
        }
        .onDisappear(perform: teardown)
    }

    // MARK: - Chrome

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

    // MARK: - The strip

    /// Everything the old card held, on one line: what the mic is hearing, how
    /// far the capture has got, and the two controls.
    ///
    /// Built like the caption strips on 2/4 and 3/4 — flexible text on the left,
    /// controls hard right — so the three setup steps read as one screen that
    /// changes its instructions rather than three screens.
    private var bottomBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    SectionLabel(learned
                                 ? "Kotek knows this gangsa's voice"
                                 : "Strike any key — soft, then hard",
                                 color: Theme.copper)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    //R What the card said in a paragraph — that the first
                    //R strikes seed the template and unlike ones are dropped —
                    //R this says at the moment it happens, which is the only
                    //R moment it means anything.
                    if let lastAccepted {
                        Label(lastAccepted ? "heard a strike" : "ignored — didn't match the others",
                              systemImage: lastAccepted ? "checkmark.circle" : "xmark.circle")
                            .font(.sans(12, weight: .medium))
                            .foregroundStyle(lastAccepted ? Theme.cream : Theme.inkStone)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }

                micVisualization(height: 26)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            strikeMeter

            PillButton(title: "Reset", style: .outlined, tint: Theme.inkStone, compact: true) { reset() }

            PillButton(title: learned ? "Continue" : "Listening…",
                       //R Only once it IS a next button. While it still
                       //R says "Listening…" it is a status, and an arrow
                       //R on a status promises something it cannot do.
                       trailingSystemImage: learned ? "arrow.right" : nil,
                       style: learned ? .filled : .outlined,
                       tint: Theme.copper,
                       compact: true) {
                if learned { commit() }
            }
            .disabled(!learned || committing)
            .opacity(learned ? 1 : 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.6)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: [.bottom, .horizontal])
        )
    }

    /// The 150pt confidence ring, shrunk to fit the strip.
    ///
    /// It reads STRIKES rather than a percentage now. The percentage was always
    /// `strikeCount / strikesNeeded` wearing a disguise, and the count is the
    /// thing the player can act on — "two more" is an instruction, "67%" is a
    /// number. It also replaces the counter that used to sit in the header.
    private var strikeMeter: some View {
        ZStack {
            Circle().stroke(Theme.copper.opacity(0.22), lineWidth: 5)
            Circle()
                .trim(from: 0, to: confidence)
                .stroke(Theme.copper, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: confidence)
            Text("\(min(strikeCount, strikesNeeded))/\(strikesNeeded)")
                .font(.serif(16))
                .foregroundStyle(Theme.cream)
                .contentTransition(.numericText())
        }
        .frame(width: 52, height: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(min(strikeCount, strikesNeeded)) of \(strikesNeeded) strikes learned")
    }

    /// A lightweight "spectrum" that pulses on each strike and decays between
    /// them — a felt sense of the mic hearing something, not a real FFT plot.
    private func micVisualization(height: CGFloat) -> some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            // micLevelTime is CACurrentMediaTime; convert both to a decay age.
            let age = max(0, CACurrentMediaTime() - micLevelTime)
            let level = Double(micLevel) * exp(-age / 0.45)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<22, id: \.self) { i in
                    let profile = Self.spectrumProfile[i % Self.spectrumProfile.count]
                    let jitter = 0.8 + 0.2 * sin(now * 6 + Double(i))
                    //R Scaled from the frame it is given rather than from a
                    //R hardcoded 88: the bars used to be drawn taller than the
                    //R box that held them, which only looked right because the
                    //R box was 72pt tall and clipping was doing the work.
                    let h = max(3, height * min(1, level * 3) * profile * jitter)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.copper.opacity(0.85))
                        .frame(width: 5, height: h)
                }
            }
            .frame(maxWidth: .infinity, minHeight: height, alignment: .bottomLeading)
        }
        .frame(height: height)
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
                withAnimation(.snappy(duration: 0.2)) { lastAccepted = progress.wasAccepted }
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

// MARK: - Strike baseline

/// A single generic "strike baseline" capture, replacing the per-key pitch
/// calibration. Vision decides *which* key was hit, so the app no longer needs a
/// fingerprint per key — only what *a* gangsa strike sounds like, enough to tell
/// a real strike from a scream, clap, or a mallet hovering over the keys. The
/// user strikes any keys a few times; the averaged spectrum becomes the optional
/// strike gate used during play.
struct StrikeBaselineView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController
    let audio: AudioEngineController

    @State private var capturing = false
    /// nil until a capture has completed; then the number of strikes learned.
    @State private var strikeCount: Int?
    @State private var busyMessage: String?

    var body: some View {
        ZStack {
            CameraPreview(camera: camera)
                .ignoresSafeArea()

            keyOutlines.ignoresSafeArea()

            VStack {
                header
                Spacer()
                panel
            }
            .padding(24)
        }
        .busy(busyMessage)
        .onAppear(perform: setup)
        .onDisappear(perform: teardown)
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            SecondaryButton(title: "Skip", systemImage: "chevron.right") {
                finish(enableGate: false)
            }
            Spacer()
            Text("Strike baseline")
                .font(.sans(17))
                .foregroundStyle(.white)
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .background(.black.opacity(0.55), in: Capsule())
            Spacer()
            Spacer().frame(width: 90)
        }
    }

    private var panel: some View {
        VStack(spacing: 16) {
            Text(statusText)
                .font(.sans(16))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            Button(action: toggleCapture) {
                HStack(spacing: 10) {
                    Image(systemName: capturing ? "checkmark" : "waveform.badge.plus")
                        .font(.title2)
                    Text(recordTitle)
                }
                .font(.sans(17))
                .foregroundStyle(capturing ? .white : .black)
                .padding(.vertical, 14)
                .padding(.horizontal, 24)
                .frame(maxWidth: 420)
                .background(capturing ? Color.red : Theme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            // `.plain`, not `.kajar` — the ONE control in the app with no tick
            // on it. This button starts the microphone learning what a strike
            // on this gangsa sounds like, and a kajar rung by the press itself
            // would still be decaying inside the first window that capture
            // records. The app would learn that a button is a strike.
            .buttonStyle(.plain)

            if let count = strikeCount, count > 0, !capturing {
                PrimaryButton(title: "Continue", systemImage: "checkmark.circle.fill") {
                    finish(enableGate: true)
                }
                .frame(width: 280)
            }
        }
        .padding(20)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
        .padding(.bottom, 16)
    }

    private var statusText: String {
        if capturing { return "Keep striking the keys a few times…" }
        switch strikeCount {
        case .none:
            return "Strike any keys a few times so the app learns what a real gangsa strike sounds like."
        case .some(0):
            return "No strikes heard — tap Start and hit a few keys."
        case .some(let n):
            return "Learned from \(n) strike\(n == 1 ? "" : "s"). You can re-record or continue."
        }
    }

    private var recordTitle: String {
        if capturing { return "Done" }
        return strikeCount == nil ? "Start listening" : "Re-record"
    }

    private var keyOutlines: some View {
        GeometryReader { geo in
            ForEach(app.profile.keys) { key in
                let rect = key.rect.rect(in: geo.size)
                RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                    .stroke(.white.opacity(0.3), lineWidth: Theme.keyOutlineWidth)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    // MARK: Capture

    private func toggleCapture() {
        if capturing {
            busyMessage = "Learning the strike…"
            audio.finishBaselineCapture { count, _ in
                strikeCount = count
                capturing = false
                busyMessage = nil
            }
        } else {
            audio.startBaselineCapture()
            capturing = true
        }
    }

    private func setup() {
        camera.start()
        try? audio.start(profile: app.profile)
    }

    private func teardown() {
        if capturing { audio.finishBaselineCapture { _, _ in } }
        audio.stop()
    }

    /// Leave for the song list. When a baseline was actually learned, turn the
    /// strike-sound gate on so it is used in play; skipping leaves vision-only
    /// (the more lenient default).
    private func finish(enableGate: Bool) {
        guard busyMessage == nil else { return }
        if enableGate, audio.hasStrikeBaseline {
            app.requireStrikeSound = true
        }
        // The profile written here carries the baseline template, so it is no
        // longer a trivial file.
        busyMessage = "Saving the gangsa…"
        Task {
            await app.baselineFinishedAsync()
            busyMessage = nil
        }
    }
}

/// One strike's diagnostics, snapshotted for the debug panel.
private struct StrikeDebug: Identifiable {
    let id = UUID()
    let keyIndex: Int
    let strikeNumber: Int
    let fundamentalHz: Double
    let amplitude: Float
    let partials: [(hz: Double, strength: Double)]
    /// Cosine vs earlier strikes on the same key (want high — consistent).
    let selfScores: [Float]
    /// Cosine vs other calibrated keys, best first (want low — separable).
    let crossScores: [(key: Int, score: Float)]
}

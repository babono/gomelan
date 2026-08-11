//
//  CalibrationView.swift
//  gomelan
//
//  Pitch calibration on the real instrument (PRD §4 Flow A steps 5–6).
//  Manual record-and-stop flow: The user taps "Record Strike" to enable
//  the mic, strikes the highlighted key, and records 3 clean strikes per key.
//  The app averages the recordings to calibrate each key.
//

import SwiftUI
import QuartzCore

struct CalibrationView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController
    let audio: AudioEngineController

    private let strikesNeeded = 3
    private let similarityThresholdCents = 60.0
    private let outlierThresholdCents = 50.0
    /// Two calibrated keys whose fingerprints score above this are too alike to
    /// tell apart at play time. Matches the bar the Python notebook scores
    /// against; real gangsa keys land around 0.42 at worst.
    private let maxTemplateSimilarity: Float = 0.5
    /// How long the mic stays open after arming. Long enough to line up the
    /// mallet and strike without hurrying, and to let the note ring.
    private let captureSeconds: TimeInterval = 2.5

    @State private var keyIndex = 0
    @State private var strikes: [Double] = []
    @State private var captured: [Int: Double] = [:]
    /// Fingerprints for the strikes recorded on the current key, and the averaged
    /// template per finished key. The fingerprint — not the pitch — is what the
    /// key is actually recognised by at play time.
    @State private var strikeFingerprints: [[Float]] = []
    @State private var capturedFingerprints: [Int: [Float]] = [:]
    @State private var message: String?
    /// Non-blocking note about a calibration that will probably work but is worth
    /// knowing about — currently only "these two keys sound alike".
    @State private var warning: String?
    @State private var lastHz: Double?
    @State private var finished = false

    @State private var isListening = false
    @State private var isArming = false
    @State private var timeoutTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            keyHighlights.ignoresSafeArea()

            VStack {
                header
                Spacer()
                if finished { summary } else { recordControlPanel }
            }
            .padding(24)
        }
        .onAppear(perform: setup)
        .onDisappear(perform: teardown)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            SecondaryButton(title: "Cancel", systemImage: "xmark") {
                app.calibrationFinished()
            }
            Spacer()
            if !finished {
                Text("Key \(keyIndex + 1) of \(app.profile.keyCount) — Highlighted Key")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(.black.opacity(0.55), in: Capsule())
            }
            Spacer()
            if keyIndex > 0 && !finished {
                SecondaryButton(title: "Redo Prev", systemImage: "arrow.uturn.backward") {
                    redoPreviousKey()
                }
            } else {
                Spacer().frame(width: 90)
            }
        }
    }

    private var recordControlPanel: some View {
        VStack(spacing: 14) {
            if let message {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.wrong)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(.black.opacity(0.6), in: Capsule())
            }

            if let warning {
                Text(warning)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(.black.opacity(0.6), in: Capsule())
            }

            // 3 Strike Badges
            HStack(spacing: 12) {
                ForEach(0..<strikesNeeded, id: \.self) { i in
                    HStack(spacing: 6) {
                        Image(systemName: i < strikes.count ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(i < strikes.count ? Theme.hit : .white.opacity(0.4))
                        if i < strikes.count {
                            Text(String(format: "%.1f Hz", strikes[i]))
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(.white)
                        } else {
                            Text("Strike \(i + 1)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(.white.opacity(0.12), in: Capsule())
                }
            }

            // Main Record Action Button
            if strikes.count < strikesNeeded {
                Button {
                    if isListening || isArming {
                        stopListening(message: nil)
                    } else {
                        startListeningForStrike()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isArming ? "hourglass" : (isListening ? "waveform.circle.fill" : "mic.fill"))
                            .font(.title2)
                        Text(isArming ? "Readying mic..." : (isListening ? "Listening... Strike Key \(keyIndex + 1) Now" : "Tap to Record Strike \(strikes.count + 1) of 3"))
                            .fontWeight(.semibold)
                    }
                    .font(.headline)
                    .foregroundStyle(isListening || isArming ? .white : .black)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 420)
                    .background(isListening ? Color.red : (isArming ? Color.orange : Theme.accent), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            } else {
                // Calculated average summary
                let avg = averageHz(for: strikes)
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.hit)
                    Text(String(format: "Average Pitch: %.1f Hz", avg))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(.black.opacity(0.6), in: Capsule())
            }

            if !strikes.isEmpty && strikes.count < strikesNeeded {
                Button("Reset strikes for Key \(keyIndex + 1)") {
                    resetCurrentKeyStrikes()
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(18)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
        .padding(.bottom, 16)
    }

    private var summary: some View {
        VStack(spacing: 14) {
            Text("All \(app.profile.keyCount) keys recorded & averaged")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(summaryLine)
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                PrimaryButton(title: "Save calibration", systemImage: "checkmark.circle.fill") {
                    save()
                }
                .frame(width: 280)
                SecondaryButton(title: "Start over", systemImage: "arrow.counterclockwise") {
                    restartCalibration()
                }
            }
        }
        .padding(20)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 16)
    }

    private var summaryLine: String {
        captured.sorted { $0.key < $1.key }
            .map { String(format: "%d: %.1fHz", $0.key, $0.value) }
            .joined(separator: "  ")
    }

    // MARK: - Key highlights

    private var keyHighlights: some View {
        GeometryReader { geo in
            ForEach(app.profile.keys) { key in
                let rect = key.rect.rect(in: geo.size)
                let shape = RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                Group {
                    if key.index == keyIndex && !finished {
                        shape.fill(Theme.upcoming.opacity(0.5))
                        shape.stroke(Theme.upcoming, lineWidth: Theme.keyOutlineWidth)
                    } else if captured[key.index] != nil {
                        shape.stroke(Theme.hit, lineWidth: Theme.keyOutlineWidth)
                    } else {
                        shape.stroke(.white.opacity(0.25), lineWidth: Theme.keyOutlineWidth)
                    }
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    // MARK: - Capture

    private func setup() {
        camera.start()
        try? audio.start(profile: app.profile)
    }

    private func teardown() {
        timeoutTask?.cancel()
        audio.cancelCapture()
        audio.onCalibrationStrike = nil
        audio.stop()
    }

    private func startListeningForStrike() {
        message = nil
        warning = nil
        isArming = true
        isListening = false
        timeoutTask?.cancel()
        timeoutTask = Task {
            // 350ms arming delay: ignores the finger-tap click sound on screen glass
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isArming = false
                isListening = true

                // Record a fixed window and keep the LOUDEST strike in it, rather
                // than stopping at the first onset. Onset detection reports plenty
                // of things that are not mallet strikes — room noise, the mallet
                // approaching, reflections — and the first of them almost never is
                // the hit. Amplitude tells them apart; timing does not.
                audio.captureStrongestStrike(duration: captureSeconds) { strike in
                    Task { @MainActor in
                        guard isListening else { return }
                        if let strike {
                            registerStrike(fingerprint: strike.fingerprint, hz: strike.fundamentalHz)
                        } else {
                            stopListening(message: "No strike heard — tap Record and strike Key \(keyIndex + 1)")
                        }
                    }
                }
            }
        }
    }

    private func stopListening(message msg: String?) {
        if isListening || isArming { audio.cancelCapture() }
        isArming = false
        isListening = false
        timeoutTask?.cancel()
        timeoutTask = nil
        if let msg { message = msg }
    }

    private func registerStrike(fingerprint: [Float], hz: Double) {
        stopListening(message: nil)
        lastHz = hz
        strikes.append(hz)
        strikeFingerprints.append(fingerprint)

        if strikes.count >= strikesNeeded {
            finalizeKey()
        }
    }

    private func finalizeKey() {
        let median = strikes.sorted()[strikes.count / 2]

        // Discard outliers: strikes more than ~50 cents off the median are mis-hits.
        // Pitch is a crude test but a serviceable one for "did they hit a
        // different key by mistake", which is all this is being asked to catch.
        var cleanIndices = strikes.indices.filter {
            abs(1200 * log2(strikes[$0] / median)) <= outlierThresholdCents
        }
        // Also non-blocking: if the strikes disagree badly, keep all three and
        // say so rather than sending the user round again. Averaging a slightly
        // noisy set beats stalling the flow during testing.
        if cleanIndices.count < 2 {
            cleanIndices = Array(strikes.indices)
            warning = "Strikes on key \(keyIndex + 1) were inconsistent — recalibrate it if it misreads"
        }

        let avgPitch = cleanIndices.map { strikes[$0] }.reduce(0, +) / Double(cleanIndices.count)

        // Average the clean fingerprints into one template. Averaging across
        // several strikes is the biggest accuracy win available — hard strikes
        // are brighter than soft ones, and a single hit captures only whichever
        // dynamic happened to be used.
        guard let template = KeyClassifier.averageFingerprints(cleanIndices.map { strikeFingerprints[$0] }) else {
            resetCurrentKeyStrikes()
            message = "Could not read those strikes — tap Record to redo key \(keyIndex + 1)"
            return
        }

        // Two keys whose templates score above the bar cannot be told apart
        // during play. Deliberately NOT blocking for now — it is reported and
        // the user moves on, rather than being forced to re-strike mid-session.
        // Revisit once there is real evidence of how often it fires.
        if let clash = capturedFingerprints.first(where: {
            cosine($0.value, template) >= maxTemplateSimilarity
        }) {
            warning = "Key \(keyIndex + 1) sounds close to key \(clash.key + 1) — they may get confused"
        }

        captured[keyIndex] = avgPitch
        capturedFingerprints[keyIndex] = template

        // Brief pause so user sees the 3rd strike checked before advancing
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            await MainActor.run {
                strikes = []
                strikeFingerprints = []
                warning = nil
                if keyIndex + 1 < app.profile.keyCount {
                    keyIndex += 1
                } else {
                    finished = true
                }
            }
        }
    }

    private func averageHz(for list: [Double]) -> Double {
        guard !list.isEmpty else { return 0 }
        return list.reduce(0.0, +) / Double(list.count)
    }

    /// Cosine similarity between two L2-normalised fingerprints — a dot product,
    /// since both sides already have unit length.
    private func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var total: Float = 0
        for i in a.indices { total += a[i] * b[i] }
        return total
    }

    private func resetCurrentKeyStrikes() {
        stopListening(message: nil)
        strikes = []
        strikeFingerprints = []
    }

    private func redoPreviousKey() {
        guard keyIndex > 0 else { return }
        stopListening(message: nil)
        keyIndex -= 1
        captured[keyIndex] = nil
        capturedFingerprints[keyIndex] = nil
        strikes = []
        strikeFingerprints = []
        message = nil
    }

    private func restartCalibration() {
        stopListening(message: nil)
        keyIndex = 0
        strikes = []
        strikeFingerprints = []
        captured = [:]
        capturedFingerprints = [:]
        finished = false
        message = nil
        warning = nil
    }

    private func save() {
        var profile = app.profile
        for i in profile.keys.indices {
            if let hz = captured[profile.keys[i].index] {
                profile.keys[i].fundamentalHz = hz
                profile.keys[i].confidence = 1.0
            }
            // The template is what matching actually uses.
            if let template = capturedFingerprints[profile.keys[i].index] {
                profile.keys[i].fingerprint = template
            }
        }
        profile.createdAt = ISO8601DateFormatter().string(from: .now)
        app.profile = profile
        app.saveProfile()
        app.calibrationFinished()
    }
}

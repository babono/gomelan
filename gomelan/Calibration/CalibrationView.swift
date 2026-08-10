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

    @State private var keyIndex = 0
    @State private var strikes: [Double] = []
    @State private var captured: [Int: Double] = [:]
    @State private var message: String?
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
        audio.onRawOnset = { hz, _ in
            Task { @MainActor in
                if isListening {
                    registerStrike(hz)
                }
            }
        }
        try? audio.start(profile: app.profile)
    }

    private func teardown() {
        timeoutTask?.cancel()
        audio.onRawOnset = nil
        audio.stop()
    }

    private func startListeningForStrike() {
        message = nil
        isArming = true
        isListening = false
        audio.resetDetector()
        timeoutTask?.cancel()
        timeoutTask = Task {
            // 350ms arming delay: ignores the finger-tap click sound on screen glass
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                audio.resetDetector()
                isArming = false
                isListening = true
            }
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled {
                await MainActor.run {
                    if isListening {
                        stopListening(message: "No strike heard — tap Record and strike Key \(keyIndex + 1)")
                    }
                }
            }
        }
    }

    private func stopListening(message msg: String?) {
        isArming = false
        isListening = false
        timeoutTask?.cancel()
        timeoutTask = nil
        if let msg { message = msg }
    }

    private func registerStrike(_ hz: Double) {
        stopListening(message: nil)
        lastHz = hz
        strikes.append(hz)

        if strikes.count >= strikesNeeded {
            finalizeKey()
        }
    }

    private func finalizeKey() {
        let median = strikes.sorted()[strikes.count / 2]

        // Discard outliers: strikes more than ~50 cents off the median are mis-hits.
        let clean = strikes.filter { abs(1200 * log2($0 / median)) <= outlierThresholdCents }
        guard clean.count >= 2 else {
            strikes = []
            message = "Strikes were inconsistent — tap Record to redo key \(keyIndex + 1)"
            return
        }

        // Calculate average pitch of clean strikes
        let avgPitch = clean.reduce(0.0, +) / Double(clean.count)

        // Check similarity to existing keys
        if let clash = captured.first(where: { abs(1200 * log2(avgPitch / $0.value)) < similarityThresholdCents }) {
            strikes = []
            message = "Too close to key \(clash.key + 1) (\(String(format: "%.1f", clash.value)) Hz) — check you struck the highlighted key"
            return
        }

        captured[keyIndex] = avgPitch
        
        // Brief pause so user sees the 3rd strike checked before advancing
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            await MainActor.run {
                strikes = []
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

    private func resetCurrentKeyStrikes() {
        stopListening(message: nil)
        strikes = []
    }

    private func redoPreviousKey() {
        guard keyIndex > 0 else { return }
        stopListening(message: nil)
        keyIndex -= 1
        captured[keyIndex] = nil
        strikes = []
        message = nil
    }

    private func restartCalibration() {
        stopListening(message: nil)
        keyIndex = 0
        strikes = []
        captured = [:]
        finished = false
        message = nil
    }

    private func save() {
        var profile = app.profile
        for i in profile.keys.indices {
            if let hz = captured[profile.keys[i].index] {
                profile.keys[i].fundamentalHz = hz
                profile.keys[i].confidence = 1.0
            }
        }
        profile.createdAt = ISO8601DateFormatter().string(from: .now)
        app.profile = profile
        app.saveProfile()
        app.calibrationFinished()
    }
}

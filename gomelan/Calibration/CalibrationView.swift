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

    /// Diagnostics for the debug panel — most recent strike first.
    @State private var debugLog: [StrikeDebug] = []
    @State private var showDebug = false

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

            if showDebug {
                debugPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 92)
                    .padding(.trailing, 16)
            }

            debugToggle
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(24)
        }
        .onAppear(perform: setup)
        .onDisappear(perform: teardown)
    }

    // MARK: - Debug panel

    private var debugToggle: some View {
        Button {
            showDebug.toggle()
        } label: {
            Image(systemName: showDebug ? "ladybug.fill" : "ladybug")
                .font(.title2)
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.5), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STRIKE DEBUG")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.6))
            if debugLog.isEmpty {
                Text("Record a strike to see how it looks digitally.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(debugLog) { entry in
                            debugRow(entry)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
    }

    private func debugRow(_ e: StrikeDebug) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Key \(e.keyIndex + 1) · strike \(e.strikeNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            Text(String(format: "f0 %.0f Hz · amp %.3f", e.fundamentalHz, e.amplitude))
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.7))
            Text("partials: " + partialText(e.partials))
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            if !e.selfScores.isEmpty {
                // Same key, earlier strikes — high means this key records consistently.
                Text("self: " + scoreText(e.selfScores))
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.hit)
            }
            // Other keys — anything at/above the similarity bar is confusable.
            ForEach(e.crossScores, id: \.key) { c in
                Text(String(format: "vs K%d: %.2f", c.key + 1, c.score))
                    .font(.caption2.monospaced())
                    .foregroundStyle(c.score >= maxTemplateSimilarity ? Theme.wrong : .white.opacity(0.55))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func partialText(_ partials: [(hz: Double, strength: Double)]) -> String {
        partials.map { String(format: "%.0f(%.2f)", $0.hz, $0.strength) }.joined(separator: " ")
    }

    private func scoreText(_ scores: [Float]) -> String {
        scores.map { String(format: "%.2f", $0) }.joined(separator: " ")
    }

    // MARK: - Record button state
    //
    // Pulled out of the view body as plainly-typed properties. Inlined as nested
    // ternaries these forced the type-checker to explore every Color/String/Image
    // combination and pushed `recordControlPanel` past 850ms to type-check.

    private var recordButtonSymbol: String {
        if isArming { return "hourglass" }
        return isListening ? "waveform.circle.fill" : "mic.fill"
    }

    private var recordButtonTitle: String {
        if isArming { return "Readying mic..." }
        if isListening { return "Listening... Strike Key \(keyIndex + 1) Now" }
        return "Tap to Record Strike \(strikes.count + 1) of 3"
    }

    private var recordButtonForeground: Color {
        (isListening || isArming) ? .white : .black
    }

    private var recordButtonBackground: Color {
        if isListening { return .red }
        return isArming ? .orange : Theme.accent
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
                        Image(systemName: recordButtonSymbol)
                            .font(.title2)
                        Text(recordButtonTitle)
                            .fontWeight(.semibold)
                    }
                    .font(.headline)
                    .foregroundStyle(recordButtonForeground)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 420)
                    .background(recordButtonBackground, in: RoundedRectangle(cornerRadius: 14))
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

            // How confusable the finished templates are with each other. Worth
            // showing while the instrument is still in front of the user — a
            // pair that cannot be told apart here will misread every session
            // afterwards, and redoing two keys now costs seconds.
            if let quality = qualityLine {
                Text(quality)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(worstSimilarity ?? 0 < maxTemplateSimilarity ? Theme.hit : Theme.accent)
                    .multilineTextAlignment(.center)
            }
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

    /// Worst cosine similarity between any two finished templates.
    private var worstPair: (Float, Int, Int)? {
        let entries = capturedFingerprints.sorted { $0.key < $1.key }
        guard entries.count >= 2 else { return nil }
        var worst: (Float, Int, Int)?
        for a in 0..<entries.count {
            for b in (a + 1)..<entries.count {
                let score = cosine(entries[a].value, entries[b].value)
                if score > (worst?.0 ?? -1) {
                    worst = (score, entries[a].key, entries[b].key)
                }
            }
        }
        return worst
    }

    private var worstSimilarity: Float? { worstPair?.0 }

    private var qualityLine: String? {
        guard let (score, a, b) = worstPair else { return nil }
        if score < maxTemplateSimilarity {
            return String(format: "Keys are well separated (closest pair %.2f)", score)
        }
        return String(format: "Keys %d and %d sound alike (%.2f) — redo them if they misread",
                      a + 1, b + 1, score)
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
                            registerStrike(strike)
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

    private func registerStrike(_ strike: AudioEngineController.CapturedStrike) {
        stopListening(message: nil)
        recordDebug(for: strike)
        lastHz = strike.fundamentalHz
        strikes.append(strike.fundamentalHz)
        strikeFingerprints.append(strike.fingerprint)

        if strikes.count >= strikesNeeded {
            finalizeKey()
        }
    }

    /// Capture how this strike looks digitally, for the debug panel: its partials,
    /// how consistent it is with earlier strikes on the SAME key (self-similarity,
    /// want high), and how close it is to the OTHER keys already calibrated this
    /// session (cross-similarity, want low — high means confusable).
    private func recordDebug(for strike: AudioEngineController.CapturedStrike) {
        let selfScores = strikeFingerprints.map { cosine($0, strike.fingerprint) }
        let crossScores = capturedFingerprints
            .map { (key: $0.key, score: cosine($0.value, strike.fingerprint)) }
            .sorted { $0.score > $1.score }

        let entry = StrikeDebug(keyIndex: keyIndex,
                                strikeNumber: strikes.count + 1,
                                fundamentalHz: strike.fundamentalHz,
                                amplitude: strike.amplitude,
                                partials: strike.topPartials,
                                selfScores: selfScores,
                                crossScores: crossScores)
        debugLog.insert(entry, at: 0)
        if debugLog.count > 8 { debugLog.removeLast(debugLog.count - 8) }
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

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            keyOutlines.ignoresSafeArea()

            VStack {
                header
                Spacer()
                panel
            }
            .padding(24)
        }
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
                .font(.headline)
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
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            Button(action: toggleCapture) {
                HStack(spacing: 10) {
                    Image(systemName: capturing ? "checkmark" : "waveform.badge.plus")
                        .font(.title2)
                    Text(recordTitle).fontWeight(.semibold)
                }
                .font(.headline)
                .foregroundStyle(capturing ? .white : .black)
                .padding(.vertical, 14)
                .padding(.horizontal, 24)
                .frame(maxWidth: 420)
                .background(capturing ? Color.red : Theme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
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
            audio.finishBaselineCapture { count in
                strikeCount = count
                capturing = false
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
        if capturing { audio.finishBaselineCapture { _ in } }
        audio.stop()
    }

    /// Leave for the song list. When a baseline was actually learned, turn the
    /// strike-sound gate on so it is used in play; skipping leaves vision-only
    /// (the more lenient default).
    private func finish(enableGate: Bool) {
        if enableGate, audio.hasStrikeBaseline {
            app.requireStrikeSound = true
        }
        app.baselineFinished()
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

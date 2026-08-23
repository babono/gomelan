//
//  DetectionTestView.swift
//  Kotek
//
//  Dev screen for the REAL practice-mode detector. Unlike MalletTestView (which
//  shows raw per-frame vision probabilities), this runs the exact pipeline that
//  play/practice uses — vision self-trigger (rising edge) + audio timing snap —
//  and reports which key it decides was hit. If a strike registers wrong here,
//  it registers wrong in practice, so this is the screen to debug the combined
//  detection on.
//

import SwiftUI
import QuartzCore
import Vision

struct DetectionTestView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController
    let audio: AudioEngineController

    @State private var fusion: StrikeFusion?
    @State private var detector = VisionStrikeDetector()
    @State private var overlaySize: CGSize = .zero

    /// Live per-key hit probabilities, for the overlay tint.
    @State private var scores: [Int: Double] = [:]

    struct Hit: Identifiable {
        let id = UUID()
        let key: Int
        let prob: Double
        let audioSnapped: Bool
        /// What the ear made of the same strike — nil when the dictionary had
        /// nothing to say (too few atoms yet, or no onset to decompose).
        var heardKey: Int?
        var heardShare: Float?
        var residual: Float?
        var heardTrusted = false

        var agrees: Bool? { heardKey.map { $0 == key } }
    }
    @State private var lastHit: Hit?
    @State private var log: [Hit] = []

    /// Dictionary state, polled rather than pushed — it lives on the DSP queue
    /// and changes a few times a second at most.
    @State private var examples: [Int: Int] = [:]
    @State private var agreement = KeyDecomposer.Agreement()
    @State private var showDictionary = true
    /// Sightings rejected for want of a strike sound.
    @State private var vetoed = 0

    /// Rising-edge threshold, tunable live.
    ///
    /// Retraining moves this. A model's output scale is a property of the data
    /// it saw, not a universal quantity: the 20-image predecessor was wildly
    /// overconfident and read 0.99 on bare wood, so 0.50 was a low bar. A model
    /// trained against four times as many negatives is calibrated far more
    /// conservatively, and the same physical strike may now read 0.55. Nothing
    /// got worse — the ruler changed. So the threshold has to be re-measured
    /// against the model in front of you, which is what this slider is for.
    /// Highest score seen since the last reset, per key — the number you
    /// actually set the threshold from.
    @State private var peakScores: [Int: Double] = [:]

    /// Which signal decides that a strike HAPPENED.
    ///
    /// The choice follows from what the model was trained to answer. A CONTACT
    /// model spikes at impact and decays, so a rising edge in the score is a
    /// strike and vision can trigger itself. A PRESENCE model reports that the
    /// mallet is over the bar, which stays true while it lingers there — the
    /// score goes up once and sits high, the Schmitt trigger latches, and every
    /// repeated note on that bar is lost.
    ///
    /// Since the retrain, the model is a presence detector. So the trigger has
    /// to come from the ear, which is impulsive by nature: an onset says a strike
    /// occurred, and vision is asked only which bar was occupied at that instant.

    /// Onset-path diagnostics. When nothing fires, these separate "the ear never
    /// reported a strike" from "it did, and vision had nothing at that instant"
    /// from "it did, vision saw something, and the threshold rejected it".
    @State private var onsetCount = 0
    @State private var resolvedCount = 0
    @State private var lastOnsetTop: [(key: Int, score: Double)] = []
    @State private var lastFrameAge: Double = 0

    /// Require the microphone to corroborate a sighting before it counts.
    ///
    /// Vision self-triggering was built to be immune to background noise, and it
    /// is — but that immunity buys false NEGATIVES at the cost of false
    /// POSITIVES, and a bilah whose rect has slipped off the instrument scores
    /// whatever the classifier happens to output on wood and cord. A gangsa
    /// strike is the loudest thing in the room; if nothing was heard, nothing
    /// was struck.

    /// Matches PlayView — only clear sightings are allowed to teach.
    private let visionTeachingConfidence: Double = 0.75
    /// How far from a sighting an onset may sit and still corroborate it. Wider
    /// than the 0.08 used for timing snap, because here it only has to prove a
    /// strike happened, not say exactly when.
    private let corroborationWindow: Double = 0.12

    var body: some View {
        @Bindable var app = app
        return ZStack {
            CameraPreview(camera: camera, forwardsRotation: true)
                .ignoresSafeArea()

            keyOverlay

            banner

            chrome
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { overlaySize = proxy.size }
                    .onChange(of: proxy.size) { _, new in overlaySize = new }
            }
            .ignoresSafeArea()
        }
        .onChange(of: overlaySize) { _, new in Task { await fusion?.setViewSize(new) } }
        .onAppear {
            camera.start()
            if app.fixedMount { camera.lockFocusAndExposure() } else { camera.enableContinuousAutoFocus() }
            fusion = StrikeFusion(frames: camera.frameBuffer,
                                  keys: app.profile.keys,
                                  viewSize: overlaySize)
            try? audio.start(profile: app.profile)
            if let baseline = app.profile.strikeBaseline {
                audio.setBaselineTemplate(baseline)
            }
            // Learn here too. This screen strikes the same instrument through the
            // same pipeline, so there is no reason a session spent debugging
            // should not also build the dictionary — and every reason to watch it
            // build somewhere the numbers are visible.
            audio.setKeyOpinionsEnabled(true)
            audio.setDecompositionKeys([])

            audio.onStrikeDetected = { hostTime in
                Task { @MainActor in
                    onsetCount += 1
                    guard app.audioTriggersStrikes, let fusion else { return }
                    guard let probe = await fusion.scoresAt(hostTime: hostTime) else { return }
                    lastFrameAge = probe.frameAge
                    lastOnsetTop = probe.scores
                        .sorted { $0.value > $1.value }
                        .prefix(3)
                        .map { (key: $0.key, score: $0.value) }
                    guard let best = lastOnsetTop.first, best.score >= app.visionThreshold else { return }
                    resolvedCount += 1
                    register(key: best.key, probability: best.score,
                             at: hostTime, snapped: true)
                }
            }
        }
        .onDisappear {
            audio.onStrikeDetected = nil
            audio.learnedTemplates { templates in app.storeLinearTemplates(templates) }
            audio.setKeyOpinionsEnabled(false)
            audio.stop()
        }
        .task { await runDetection() }
        .task { await pollDictionary() }
        .onChange(of: app.visionThreshold) { _, new in
            Task { await fusion?.setMinHitProbability(new * 0.9) }
        }
    }

    // MARK: - Overlay

    private var keyOverlay: some View {
        GeometryReader { geometry in
            ForEach(app.profile.keys) { key in
                let prob = scores[key.index] ?? 0
                // Tinted against the SAME bar the detector uses, so the colours
                // never disagree with the decisions. A fixed 0.5 here meant a key
                // could register a strike while still drawing white.
                let isHit = prob >= app.visionThreshold
                let justFired = lastHit?.key == key.index
                let rect = key.rect.rect(in: geometry.size)

                RoundedRectangle(cornerRadius: 6)
                    .stroke(justFired ? Theme.accent : (isHit ? Color.green : .white.opacity(0.35)),
                            lineWidth: justFired ? 4 : (isHit ? 3 : 1.5))
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.green.opacity(isHit ? 0.3 * prob : 0))
                    )
                    .overlay(alignment: .top) {
                        Text("\(key.index) · \(Int(prob * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(isHit ? .green : .white.opacity(0.7))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule())
                            .offset(y: -18)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Centre banner (last detected hit)

    private var banner: some View {
        VStack {
            Spacer()
            if let hit = lastHit {
                VStack(spacing: 6) {
                    Text("KEY \(hit.key)")
                        .font(.system(size: 72, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    HStack(spacing: 8) {
                        Image(systemName: hit.audioSnapped ? "waveform.badge.checkmark" : "eye")
                        Text(hit.audioSnapped ? "vision + audio" : "vision only")
                        Text("· \(Int(hit.prob * 100))%")
                    }
                    .font(.subheadline.weight(.semibold).monospaced())
                    .foregroundStyle(hit.audioSnapped ? Theme.hit : .white.opacity(0.7))

                    // What the ear independently made of the same strike. Shown
                    // untrusted-and-all: watching it be wrong early, then come
                    // right as atoms fill in, is the point of the screen.
                    if let heardKey = hit.heardKey {
                        HStack(spacing: 6) {
                            Image(systemName: hit.agrees == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                            Text("ear: \(heardKey)")
                            if let share = hit.heardShare {
                                Text("\(Int(share * 100))%")
                            }
                            if !hit.heardTrusted {
                                Text("· learning")
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(hit.agrees == true ? Theme.hit : Theme.wrong)
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 18)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
                .id(hit.id) // re-trigger the animation on each new hit
                .transition(.scale.combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: lastHit?.id)
    }

    // MARK: - Chrome (back, mic status, recent log)

    private var chrome: some View {
        VStack {
            HStack(spacing: 16) {
                SecondaryButton(title: "Back", systemImage: "chevron.left") {
                    app.closeDetectionTest()
                }
                Spacer()
                HStack(spacing: 8) {
                    Circle()
                        .fill(audio.isRunning ? Theme.hit : Theme.miss)
                        .frame(width: 10, height: 10)
                    Text("vision + audio")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.black.opacity(0.6), in: Capsule())
            }
            .padding(.horizontal, 24).padding(.top, 24)

            HStack(alignment: .top) {
                if showDictionary { dictionaryPanel } else { dictionaryToggle }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)

            Spacer()

            if !log.isEmpty {
                HStack(spacing: 8) {
                    ForEach(log) { hit in
                        HStack(spacing: 4) {
                            Text("\(hit.key)").fontWeight(.bold)
                            Image(systemName: hit.audioSnapped ? "waveform" : "eye")
                                .font(.system(size: 9))
                        }
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.black.opacity(0.5), in: Capsule())
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }

    /// Record a decided strike: show it, log it, tally the ear against the eye,
    /// and let a confident sighting teach the dictionary.
    private func register(key: Int, probability: Double, at hostTime: Double,
                          snapped: Bool, prebuilt: Hit? = nil) {
        var hit = prebuilt ?? Hit(key: key, prob: probability, audioSnapped: snapped)
        if prebuilt == nil, let heard = audio.debugOpinion(at: hostTime) {
            hit.heardKey = heard.best?.keyIndex
            hit.heardShare = heard.best?.share
            hit.residual = heard.residual
            hit.heardTrusted = heard.isTrusted
        }

        audio.noteVisionDecision(key, confidence: probability, at: hostTime)
        if probability >= visionTeachingConfidence {
            audio.learnKey(key, at: hostTime)
        }

        lastHit = hit
        log.append(hit)
        if log.count > 8 { log.removeFirst(log.count - 8) }
    }

    // MARK: - Dictionary readout

    /// Polled, not pushed: the decomposer lives on the DSP queue and these
    /// numbers move slowly enough that twice a second is more than honest.
    private func pollDictionary() async {
        while !Task.isCancelled {
            audio.decompositionProgress { examples = $0 }
            audio.agreementStats { agreement = $0 }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    /// The panel is HEIGHT-CAPPED and scrolls internally, and that is not a
    /// cosmetic choice. It sits in a full-size chrome layer inside the same
    /// ZStack as `keyOverlay`; left to grow past the screen it inflates the
    /// stack, and both the overlay's GeometryReader and `overlaySize` then read
    /// that inflated height. The rects visibly shift — and worse, `overlaySize`
    /// is what `CropMapper` maps through, so the crops being classified silently
    /// stop matching the boxes on screen. A debug readout must never move the
    /// thing it is reporting on.
    private var dictionaryPanel: some View {
        // Needed here as well as in `body`: `$app` bindings only exist where a
        // @Bindable local is in scope, and this is a separate computed property.
        @Bindable var app = app
        return VStack(alignment: .leading, spacing: 8) {
            // Header stays pinned so the collapse control is always reachable.
            HStack(spacing: 8) {
                Text("DICTIONARY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.copper)
                Spacer()
                Button { showDictionary.toggle() } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.vertical, showsIndicators: true) {
              VStack(alignment: .leading, spacing: 10) {
            // Onset path first: when detection stops working this is the only
            // part anyone needs, and it was sitting below ten rows of pips.
            Text("ONSET PATH")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.wrong)

            statRow("model", MalletHitClassifier.loaded ? "loaded" : "FAILED")

            // Cycle the resize and watch the live percentages on the overlay.
            // The correct one makes a struck bar read high; the wrong ones pin
            // everything near zero, which is exactly the symptom.
            HStack(spacing: 4) {
                ForEach(Array(MalletHitClassifier.cropScaleOptions.enumerated()), id: \.offset) { i, mode in
                    Button {
                        app.cropScaleMode = i
                        MalletHitClassifier.applyCropScale(mode: i)
                        peakScores.removeAll()
                    } label: {
                        Text(mode.name)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(app.cropScaleMode == i ? Theme.ink : .white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(app.cropScaleMode == i ? Theme.copper : .white.opacity(0.15),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let failure = MalletHitClassifier.lastFailure {
                Text(failure)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.wrong)
                    .fixedSize(horizontal: false, vertical: true)
            }
            statRow("audio onsets", "\(onsetCount)")
            statRow("resolved", "\(resolvedCount)")
            statRow("frame age", String(format: "%.0f ms", lastFrameAge * 1000))
            if !lastOnsetTop.isEmpty {
                Text("at last onset:")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                ForEach(lastOnsetTop, id: \.key) { entry in
                    Text(String(format: "   k%02d  %.2f", entry.key, entry.score))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(entry.score >= app.visionThreshold ? Theme.hit : Theme.wrong)
                }

            Divider().overlay(Color.white.opacity(0.2))

            // Per-key example counts. A key needs `strikesToTrustAtom` before it
            // can be recognised at all, so the bar is the thing to watch.
            VStack(alignment: .leading, spacing: 3) {
                ForEach(app.profile.keys) { key in
                    let count = examples[key.index] ?? 0
                    let trusted = count >= KeyDecomposer.strikesToTrustAtom
                    HStack(spacing: 6) {
                        Text(String(format: "%2d", key.index))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                        // Filled pips up to the trust threshold, then a count.
                        HStack(spacing: 2) {
                            ForEach(0..<KeyDecomposer.strikesToTrustAtom, id: \.self) { i in
                                Circle()
                                    .fill(i < count ? Theme.hit : Color.white.opacity(0.18))
                                    .frame(width: 5, height: 5)
                            }
                        }
                        Text(trusted ? "×\(count)" : "")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.hit.opacity(0.9))
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.2))

            let decided = agreement.agreed + agreement.disagreed
            statRow("agree", decided > 0
                    ? "\(agreement.agreed)/\(decided)  \(Int(agreement.agreementRate * 100))%"
                    : "—")
            statRow("recovered", "\(agreement.recovered)")
            statRow("no opinion", "\(agreement.noOpinion)")
            statRow("quarantined", "\(agreement.quarantined)")
            statRow("silent-vetoed", "\(vetoed)")
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("threshold")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Text(String(format: "%.2f", app.visionThreshold))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.copper)
                }
                Slider(value: $app.visionThreshold, in: 0.05...0.95, step: 0.05)
                    .tint(Theme.copper)
                    .frame(height: 20)
                // Peak score since reset. Strike each bilah a few times, read the
                // highest number here, and set the threshold below it.
                HStack {
                    Text("peak seen")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Text(peakScores.values.max().map { String(format: "%.2f", $0) } ?? "—")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.hit)
                    Button { peakScores.removeAll() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }

            Toggle(isOn: $app.audioTriggersStrikes) {
                Text("audio triggers")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .toggleStyle(.switch)
            .tint(Theme.copper)
            .scaleEffect(0.75, anchor: .leading)
            .frame(height: 22)

            // Only meaningful when vision self-triggers. With the ear driving,
            // a sound is what started the event, so there is nothing to veto —
            // greyed rather than hidden so the relationship stays visible.
            Toggle(isOn: $app.requireOnsetCorroboration) {
                Text(app.audioTriggersStrikes ? "require sound (n/a)" : "require sound")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(app.audioTriggersStrikes ? 0.3 : 0.75))
            }
            .disabled(app.audioTriggersStrikes)
            .toggleStyle(.switch)
            .tint(Theme.hit)
            .scaleEffect(0.75, anchor: .leading)
            .frame(height: 22)

            // The disagreements are the point of the whole panel. A cluster on
            // one bilah means that key's aligned rect is wrong — a calibration
            // bug, not a fusion one.
            if !agreement.recent.isEmpty {
                Divider().overlay(Color.white.opacity(0.2))
                Text("EYE ≠ EAR")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.wrong)
                ForEach(Array(agreement.recent.suffix(4).enumerated()), id: \.offset) { _, d in
                    Text("saw \(d.visionKey) (\(Int(d.visionConfidence * 100))%) · heard \(d.heardKey) (\(Int(d.heardShare * 100))%)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
              }
              }
            }
            .frame(maxHeight: panelContentHeight)
        }
        .padding(12)
        .frame(width: 210, alignment: .leading)
        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Cap for the scrolling body, measured against the live layout rather than
    /// hard-coded, so it stays inside the screen in either orientation and on
    /// iPad. Falls back to a conservative value before the first layout pass.
    ///
    /// The upper clamp closes a feedback loop: this reads `overlaySize`, which is
    /// measured from the same ZStack the panel sits in. Without a ceiling, an
    /// inflated stack would raise the cap, which would grow the panel, which
    /// would inflate the stack again. The absolute limit means the height can
    /// never be argued upwards no matter what the geometry reports.
    private var panelContentHeight: CGFloat {
        guard overlaySize.height > 0 else { return 200 }
        return min(300, max(120, overlaySize.height - 150))
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
    }

    private var dictionaryToggle: some View {
        Button { showDictionary = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "waveform.and.magnifyingglass")
                Text("dict")
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.black.opacity(0.6), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detection loop (identical to PlayView.runVisionDetection)

    private func runDetection() async {
        detector.reset()
        await fusion?.setMinHitProbability(app.visionThreshold * 0.9)
        while !Task.isCancelled {
            if overlaySize.width > 0, let (s, hostTime) = await fusion?.latestScores() {
                scores = s
                for (k, v) in s where v > (peakScores[k] ?? 0) { peakScores[k] = v }
                detector.enter = app.visionThreshold
                //R The slider drives BOTH bars: the expected key sits a little
                //R under it, everything else a little over. This screen has no
                //R figure running, so nothing is ever expected and only `enter`
                //R is actually in play — but leaving them unlinked would have
                //R the slider tuning a threshold the play screen no longer uses.
                detector.enterExpected = app.visionThreshold * 0.76
                // Re-arm well below the trigger so one strike cannot fire twice,
                // while still clearing between genuine repeated notes.
                detector.exit = app.visionThreshold * 0.6
                let fired = app.audioTriggersStrikes
                    ? []
                    : detector.process(scores: s, now: hostTime)
                if let key = fired.max(by: { (s[$0] ?? 0) < (s[$1] ?? 0) }) {
                    let onset = audio.nearestOnset(to: hostTime, within: 0.08)
                        ?? audio.nearestOnset(to: hostTime, within: corroborationWindow)
                    // Silence vetoes the sighting. Counted, so the screen can show
                    // how much of the noise this is removing.
                    if app.requireOnsetCorroboration, onset == nil {
                        vetoed += 1
                        continue
                    }
                    let strikeTime = onset ?? hostTime
                    let probability = s[key] ?? 0

                    // What the ear made of it — shown even when the residual bar
                    // has not been earned yet, which is most of the early session.
                    let heard = audio.debugOpinion(at: strikeTime)
                    var hit = Hit(key: key, prob: probability, audioSnapped: onset != nil)
                    if let heard {
                        hit.heardKey = heard.best?.keyIndex
                        hit.heardShare = heard.best?.share
                        hit.residual = heard.residual
                        hit.heardTrusted = heard.isTrusted
                    }

                    register(key: key, probability: probability,
                             at: strikeTime, snapped: onset != nil, prebuilt: hit)
                }
            }
            try? await Task.sleep(for: .milliseconds(60))
        }
    }
}

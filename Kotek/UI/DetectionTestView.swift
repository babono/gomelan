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

    /// The marker path, running instead of the classifier when it is switched
    /// on. Held alongside rather than behind a protocol: the two answer
    /// different questions per frame — probabilities per key versus a position
    /// and a trajectory — and flattening that into one interface would hide the
    /// difference this screen exists to show.
    @State private var markerFusion: MarkerFusion?
    @State private var markerFrame: MarkerFusion.Frame?
    /// Frames since the last one that contained a marker. The number that tells
    /// you the tape has rolled out of view, which is this path's whole failure
    /// mode and is invisible from the strike log alone.
    @State private var markerMisses = 0
    /// Frames actually scanned. A counter that never moves means the camera is
    /// not delivering, which looks identical from the blob count alone.
    @State private var markerScans = 0
    /// Front-view band edges, mirrored from the fusion actor so the overlay can
    /// draw the same lines the decision uses. Recomputed whenever the geometry
    /// changes rather than per frame.
    @State private var bandEdges: [Double] = []
    /// Sightings the marker gate threw out on the classifier path, and why the
    /// last one went.
    @State private var gateVetoed = 0
    @State private var lastGate: String?
    /// Turnaround time minus the ear's onset, in ms, for the last strike the
    /// microphone also heard.
    ///
    /// The one number that decides whether this path can run without audio at
    /// all. The claim marker mode rests on is that the moment the tip reverses
    /// IS the attack; the ear already knows when the attack was, so the two can
    /// simply be subtracted. A bias here is fine and correctable — a spread is
    /// not, and would mean the turnaround is being found somewhere other than
    /// the impact.
    @State private var markerTimingErrorMs: Double?

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

    var body: some View {
        @Bindable var app = app
        return ZStack {
            CameraPreview(camera: camera, forwardsRotation: true)
                .ignoresSafeArea()

            keyOverlay

            if app.markerVision { markerOverlay }

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
        .onChange(of: overlaySize) { _, new in
            Task {
                await fusion?.setViewSize(new)
                await markerFusion?.setViewSize(new)
            }
        }
        .onAppear {
            camera.start()
            if app.fixedMount { camera.lockFocusAndExposure() } else { camera.enableContinuousAutoFocus() }
            fusion = StrikeFusion(frames: camera.frameBuffer,
                                  keys: app.profile.keys,
                                  viewSize: overlaySize)
            markerFusion = MarkerFusion(frames: camera.frameBuffer,
                                        keys: app.profile.keys,
                                        viewSize: overlaySize)
            applyMarkerSettings()
            //R After the focus/exposure calls above, never before: those set an
            //R exposure mode, and marker vision has to be the last word on it.
            configureMarkerCamera()
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
                    //R The ear-triggered path gets the gate too. It did not, at
                    //R first, and the result was a screen where turning the gate
                    //R on changed nothing in the default mode — because the ear
                    //R is what triggers by default, and this closure never asked.
                    guard await markerAllows(key: best.key, at: hostTime) else { return }
                    resolvedCount += 1
                    register(key: best.key, probability: best.score,
                             at: hostTime, snapped: true)
                }
            }
        }
        .onDisappear {
            //R The torch is the one thing here that outlives the screen if it
            //R is not put back. It stays lit through the whole app — and on the
            //R lock screen — until something turns it off.
            camera.setMarkerVision(false)
            audio.onStrikeDetected = nil
            audio.learnedAtoms { templates in app.storeLinearTemplates(templates) }
            audio.setKeyOpinionsEnabled(false)
            audio.stop()
        }
        .task { await runDetection() }
        .task { await pollDictionary() }
        //R One watch, not a dozen. Every marker slider used to carry its own
        //R `.onChange`, and the chain grew until the type checker gave up on
        //R `body` outright — the failure is reported at whatever line it happens
        //R to be looking at, which is nowhere near the cause.
        .onChange(of: markerSettingsSignature) { _, _ in applyMarkerSettings() }
        .onChange(of: app.visionThreshold) { _, new in
            Task { await fusion?.setMinHitProbability(Detection.namingThreshold(from: new)) }
        }
        .onChange(of: app.requireMarker) { _, _ in
            configureMarkerCamera()
            gateVetoed = 0
            lastGate = nil
        }
        .onChange(of: app.markerVision) { _, _ in
            configureMarkerCamera()
            markerMisses = 0
            markerScans = 0
            gateVetoed = 0
            lastGate = nil
            markerFrame = nil
            peakScores.removeAll()
            Task { await markerFusion?.reset() }
        }
        .onChange(of: app.markerExposureBias) { _, _ in configureMarkerCamera() }
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

    // MARK: - Marker overlay

    /// What the tracker actually found, drawn on the frame it found it in.
    ///
    /// Worth having rather than trusting the strike log: almost every way this
    /// path goes wrong is visible here and nowhere else — one blob instead of
    /// two (the shaft band is hidden, so the tip is being guessed rather than
    /// extrapolated), a tip that sits short of where the mallet meets the bar
    /// (`tipExtension` is wrong for how the tape was applied), or a scatter of
    /// small blobs across the frame (the threshold is letting the room in).
    private var markerOverlay: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Front view names a bilah by which vertical band the marker's
                // x falls in, so the bands have to be visible — a wrong band is
                // indistinguishable from a wrong detection when all you can see
                // is the key it named.
                if app.markerPOV == MarkerPOV.front.rawValue {
                    ForEach(Array(bandEdges.enumerated()), id: \.offset) { _, edge in
                        Rectangle()
                            .fill(Theme.copper.opacity(0.5))
                            .frame(width: 1, height: geometry.size.height)
                            .position(x: edge * geometry.size.width, y: geometry.size.height / 2)
                    }
                    if app.markerROITop > 0 {
                        Rectangle()
                            .fill(.black.opacity(0.45))
                            .frame(height: app.markerROITop * geometry.size.height)
                            .position(x: geometry.size.width / 2,
                                      y: app.markerROITop * geometry.size.height / 2)
                    }
                }
                if let frame = markerFrame {
                    ForEach(Array(frame.blobs.enumerated()), id: \.offset) { i, blob in
                        let r = CGRect(x: blob.minX * geometry.size.width,
                                       y: blob.minY * geometry.size.height,
                                       width: blob.width * geometry.size.width,
                                       height: blob.height * geometry.size.height)
                        Rectangle()
                            .stroke(i == 0 ? Theme.accent : Theme.copper, lineWidth: 2)
                            .frame(width: max(r.width, 6), height: max(r.height, 6))
                            .position(x: r.midX, y: r.midY)
                    }
                    if let tip = frame.tip {
                        // A cross, not a dot: the tip is usually an
                        // extrapolation past the head marker, so it needs to be
                        // readable when it lands on top of one of the boxes.
                        Path { path in
                            let p = CGPoint(x: tip.x * geometry.size.width,
                                            y: tip.y * geometry.size.height)
                            path.move(to: CGPoint(x: p.x - 12, y: p.y))
                            path.addLine(to: CGPoint(x: p.x + 12, y: p.y))
                            path.move(to: CGPoint(x: p.x, y: p.y - 12))
                            path.addLine(to: CGPoint(x: p.x, y: p.y + 12))
                        }
                        .stroke(Theme.hit, lineWidth: 2)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    /// Torch and exposure, given what both switches want.
    ///
    /// THE EXPOSURE IS DELIBERATELY NOT CRUSHED WHEN THE MARKER IS ONLY GATING.
    /// Marker mode pulls the scene down several stops so the tape is the one
    /// bright thing in frame — but in gate mode the classifier is still the
    /// detector, and it was trained on normally exposed crops. Handing it a
    /// scene at -2.5 EV would be the `.scaleFill` mistake again: a model shown a
    /// different picture than it learned from, silently returning nothing.
    ///
    /// Gate mode borrows only the torch. Retroreflection is strong enough that
    /// the marker still pegs its channel at normal exposure, which is all the
    /// gate needs — it asks "was the mallet there", not "which bar".
    ///
    /// The torch alone still changes the scene the classifier sees, and it was
    /// trained without one. Watch the live per-key percentages when switching
    /// this on: if they collapse, that is the cause, and the fix is training
    /// crops with the torch lit rather than tuning anything here.
    private func configureMarkerCamera() {
        camera.setMarkerVision(app.markerVision || app.requireMarker,
                               exposureBias: app.markerVision ? app.markerExposureBias : 0)
    }

    /// Ask the marker whether the mallet was where the classifier says it was.
    ///
    /// Records WHY when it says no. A bare veto count told you the gate was
    /// removing strokes but not whether it was removing phantom ones (the
    /// point) or real ones because the tape had rolled out of view (the thing
    /// that would quietly ruin a session).
    private func markerAllows(key: Int, at hostTime: Double) async -> Bool {
        guard app.requireMarker, let markerFusion else { return true }
        switch await markerFusion.gate(keyIndex: key, at: hostTime,
                                       margin: app.markerGateMargin,
                                       within: Detection.corroborationWindow) {
        case .allow:
            lastGate = nil
            return true
        case .noScan:
            lastGate = "no marker scan yet"
        case .stale(let age):
            lastGate = String(format: "scan %.0f ms stale", age * 1000)
        case .noMallet:
            lastGate = "no mallet in frame"
        case .elsewhere(let other):
            lastGate = other.map { "mallet was over k\($0)" } ?? "mallet off the keys"
        }
        gateVetoed += 1
        return false
    }

    /// Keep a marker scan fresh while the CLASSIFIER is the detector, so the
    /// gate has something recent to answer from. Cheap enough to run at the
    /// classifier's own rate: one pass over a 320-wide frame, no CoreML.
    private func refreshMarkerForGate() async {
        guard app.requireMarker, !app.markerVision,
              let frame = await markerFusion?.poll() else { return }
        markerFrame = frame
        markerScans += 1
    }

    /// Every value `applyMarkerSettings` pushes into the fusion actor, in one
    /// Equatable bundle so a single `.onChange` can watch the lot.
    private var markerSettingsSignature: [Double] {
        [app.markerBrightness, Double(app.markerColour), app.markerSaturationFloor,
         app.markerSaturation, app.markerMinSpeed, app.markerTipExtension,
         app.markerROITop, Double(app.markerPOV), app.markerBandLeft,
         app.markerBandRight, app.markerBandSkew, app.markerBandFlip ? 1 : 0]
    }

    private func applyMarkerSettings() {
        Task {
            await markerFusion?.setBrightnessThreshold(Int(app.markerBrightness))
            await markerFusion?.setColour(MarkerColour(rawValue: app.markerColour) ?? .red)
            await markerFusion?.setSaturationFloor(Int(app.markerSaturationFloor))
            await markerFusion?.setROITop(app.markerROITop)
            await markerFusion?.setPOV(MarkerPOV(rawValue: app.markerPOV) ?? .top)
            await markerFusion?.setBands(left: app.markerBandLeft, right: app.markerBandRight,
                                         skew: app.markerBandSkew, flip: app.markerBandFlip)
            bandEdges = await markerFusion?.bandEdges() ?? []
            await markerFusion?.setMinApproachSpeed(app.markerMinSpeed)
            await markerFusion?.setTipExtension(app.markerTipExtension)
            await markerFusion?.setSaturationCeiling(Int(app.markerSaturation))
        }
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
            // MARKER first, above the onset path, because it is the switch
            // that decides which of the two detectors everything below is even
            // describing. Buried under the classifier's diagnostics it read as
            // one more tuning knob rather than a fork.
            Text("MARKER")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)

            Toggle(isOn: $app.markerVision) {
                Text("track marker")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .tint(Theme.copper)

            if app.markerVision {
                // Lit fraction is the exposure gauge, and the first thing to
                // get right — every other number here is meaningless until the
                // marker is the only bright thing in the frame. A tuned rig
                // sits well under a percent; a whole percent means the room is
                // coming through and blobs are about to appear on bronze.
                // The first thing to get right, and the one setting that is a
                // fact about the mallet rather than a dial: everything below
                // means something different depending on it.
                HStack(spacing: 4) {
                    ForEach(MarkerColour.allCases, id: \.rawValue) { c in
                        Button { app.markerColour = c.rawValue } label: {
                            Text(c.name)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(app.markerColour == c.rawValue ? Theme.ink : .white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(app.markerColour == c.rawValue ? Theme.copper : .white.opacity(0.15),
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(MarkerColour(rawValue: app.markerColour)?.note ?? "")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    ForEach(MarkerPOV.allCases, id: \.rawValue) { p in
                        Button { app.markerPOV = p.rawValue } label: {
                            Text(p.name)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(app.markerPOV == p.rawValue ? Theme.ink : .white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(app.markerPOV == p.rawValue ? Theme.accent : .white.opacity(0.15),
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if app.markerPOV == MarkerPOV.front.rawValue {
                    Toggle(isOn: $app.markerBandFlip) {
                        Text("key 0 on right")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.copper)
                    tuningRow("band left", value: $app.markerBandLeft, range: 0...1, step: 0.01,
                              display: String(format: "%.2f", app.markerBandLeft))
                    tuningRow("band right", value: $app.markerBandRight, range: 0...1, step: 0.01,
                              display: String(format: "%.2f", app.markerBandRight))
                    tuningRow("band skew", value: $app.markerBandSkew, range: (-0.6)...0.6, step: 0.02,
                              display: String(format: "%+.2f", app.markerBandSkew))
                    tuningRow("horizon", value: $app.markerROITop, range: 0...0.8, step: 0.02,
                              display: String(format: "%.2f", app.markerROITop))
                }

                let lit = (markerFrame?.litFraction ?? 0) * 100
                statRow("scans", "\(markerScans)")
                statRow("blobs", "\(markerFrame?.blobs.count ?? 0)")
                statRow("lit", String(format: "%.2f %%", lit))
                statRow("lost frames", "\(markerMisses)")

                // The three-way split on "no blobs". Read top to bottom: is
                // anything bright enough, did it survive the colour test, and
                // only then is it worth touching any other slider.
                if let f = markerFrame {
                    statRow("max bright", "\(f.maxBrightness) (spread \(f.spreadAtMaxBrightness))")
                    statRow("bright pass", "\(f.brightnessPassed)")
                    statRow("colour reject", "\(f.colourRejected)")

                    if f.blobs.isEmpty {
                        if f.maxBrightness < Int(app.markerBrightness) {
                            Text("nothing reaches \(Int(app.markerBrightness)) — torch off, or EV too low")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Theme.wrong)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if f.colourRejected > f.brightnessPassed / 2 {
                            Text("bright, but the wrong colour for \(MarkerColour(rawValue: app.markerColour)?.name ?? "?")")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Theme.wrong)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("passing pixels, all too small — lower min area")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Theme.wrong)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let err = markerTimingErrorMs {
                    statRow("vs onset", String(format: "%+.0f ms", err))
                }
                if lit > 1.0 {
                    Text("scene leaking — lower EV or raise luma")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.wrong)
                        .fixedSize(horizontal: false, vertical: true)
                }

                tuningRow("brightness", value: $app.markerBrightness, range: 100...254, step: 1,
                          display: String(format: "%.0f", app.markerBrightness))
                if app.markerColour == MarkerColour.white.rawValue {
                    tuningRow("sat ceiling", value: $app.markerSaturation, range: 10...200, step: 5,
                              display: String(format: "%.0f", app.markerSaturation))
                } else {
                    tuningRow("colour lead", value: $app.markerSaturationFloor, range: 10...200, step: 5,
                              display: String(format: "%.0f", app.markerSaturationFloor))
                }
                tuningRow("EV", value: $app.markerExposureBias, range: (-8)...0, step: 0.5,
                          display: String(format: "%.1f", app.markerExposureBias))
                tuningRow("min speed", value: $app.markerMinSpeed, range: 0.001...0.02, step: 0.001,
                          display: String(format: "%.3f", app.markerMinSpeed))
                // Set this one by eye against the overlay cross, not by the
                // strike log: it is the only marker setting whose effect is
                // fully visible in a still frame, and the only one you can get
                // right while holding the mallet against a bar without playing.
                tuningRow("tip reach", value: $app.markerTipExtension, range: 0...1, step: 0.05,
                          display: String(format: "%.2f", app.markerTipExtension))
            }

            if !app.markerVision {
                Divider().overlay(Color.white.opacity(0.2))
                Text("MARKER GATE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                Toggle(isOn: $app.requireMarker) {
                    Text("marker must vouch")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .toggleStyle(.switch)
                .tint(Theme.copper)
                if app.requireMarker {
                    Text("torch on, exposure left alone — the classifier is still the detector")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                    statRow("gate vetoed", "\(gateVetoed)")
                    if let lastGate {
                        Text(lastGate)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.wrong)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    tuningRow("gate margin", value: $app.markerGateMargin, range: 0...0.3, step: 0.01,
                              display: String(format: "%.2f", app.markerGateMargin))
                }
            }

            Divider().overlay(Color.white.opacity(0.2))

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
                tuningRow("re-arm dip", value: $app.visionRelativeDip, range: 0.02...0.40, step: 0.01,
                          display: String(format: "%.2f", app.visionRelativeDip))
                Text("lower = repeated strokes on one bar register; too low = one stroke fires twice")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
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

            //R THE Detection setting from Settings, not a second one that only
            //R existed here. Two switches meaning the same thing on two screens
            //R is how a debug screen ends up testing something the app does not
            //R do — which is exactly what had happened.
            Toggle(isOn: Binding(get: { app.requireStrikeSound },
                                 set: { app.requireStrikeSound = $0 })) {
                Text("heard only")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
            }
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

    /// A label, the live value, and the slider that moves it, on two lines.
    ///
    /// The value is shown as text as well as by the knob because these are
    /// numbers you write down and re-enter on another instrument — a slider
    /// position is not something you can carry to the next gangsa.
    private func tuningRow(_ label: String, value: Binding<Double>,
                           range: ClosedRange<Double>, step: Double,
                           display: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(label)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(display)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            Slider(value: value, in: range, step: step)
                .tint(Theme.copper)
        }
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

    //R The same decision path as `PlayView.runVisionDetection`, and now
    //R actually the same: both call `detector.apply(threshold:)`, both read
    //R `Detection.corroborationWindow`, both veto on `app.requireStrikeSound`,
    //R and vision self-triggers in both regardless of what the ear is doing.
    //R The claim was here before the code matched it, which is the worst kind
    //R of comment on a debug screen — it is the reason to trust what you are
    //R watching.

    private func runDetection() async {
        detector.reset()
        await fusion?.setMinHitProbability(Detection.namingThreshold(from: app.visionThreshold))
        while !Task.isCancelled {
            if app.markerVision {
                await stepMarker()
                //R Faster than the classifier poll, and it has to be. That path
                //R scores whatever frame is newest and does not care what it
                //R missed; this one is reconstructing a TRAJECTORY, and at 60ms
                //R against a 30fps camera it sampled every other frame, which
                //R halved the resolution of the very turnaround it is looking
                //R for and dropped short strokes entirely.
                try? await Task.sleep(for: .milliseconds(20))
                continue
            }
            await refreshMarkerForGate()
            if overlaySize.width > 0, let (s, hostTime) = await fusion?.latestScores() {
                scores = s
                for (k, v) in s where v > (peakScores[k] ?? 0) { peakScores[k] = v }
                //R One call, the same one the play screen makes. These were
                //R set by hand here and hardcoded there, so the slider tuned a
                //R threshold no session used.
                detector.apply(threshold: app.visionThreshold, relativeDip: app.visionRelativeDip)

                //R Vision ALWAYS runs, exactly as it does in play. This used to
                //R return nothing whenever the ear was allowed to trigger — and
                //R since the ear is allowed to by default, the screen built for
                //R watching vision showed none of it.
                let fired = detector.process(scores: s, now: hostTime)
                if let key = fired.max(by: { (s[$0] ?? 0) < (s[$1] ?? 0) }) {
                    let onset = audio.nearestOnset(to: hostTime,
                                                   within: Detection.corroborationWindow)
                    //R The Detection setting, not a second one that only exists
                    //R here. Silence vetoes the sighting in Heard only; counted,
                    //R so the screen can show how much it is removing.
                    if app.requireStrikeSound, onset == nil {
                        vetoed += 1
                        continue
                    }
                    let strikeTime = onset ?? hostTime
                    guard await markerAllows(key: key, at: strikeTime) else { continue }
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

    /// One poll of the marker path.
    ///
    /// Kept out of the loop body rather than inlined beside the classifier
    /// branch: the two share nothing except the loop. Different signal, different
    /// state, and — the part that matters when reading this screen — a different
    /// account of what went wrong when nothing fires.
    private func stepMarker() async {
        guard overlaySize.width > 0, let frame = await markerFusion?.poll() else { return }
        markerFrame = frame
        markerScans += 1
        if frame.tip == nil { markerMisses += 1 } else { markerMisses = 0 }
        guard let event = frame.event else { return }

        let onset = audio.nearestOnset(to: event.hostTime, within: Detection.corroborationWindow)
        if let onset { markerTimingErrorMs = (event.hostTime - onset) * 1000 }
        //R The ear keeps its veto here too, on the same setting. Marker mode is
        //R meant to run without it — that is the whole point of the exhibition
        //R path — but leaving the switch connected is what lets you measure how
        //R much it would have removed before trusting the camera alone.
        if app.requireStrikeSound, onset == nil {
            vetoed += 1
            return
        }
        //R `event.hostTime` unchanged, deliberately: the classifier path snaps
        //R its time to the onset because a sighting is an arrival, not an
        //R attack. Snapping here would erase the difference this path claims to
        //R make, and `markerTimingErrorMs` above would then only be measuring
        //R itself. The ear is recorded as agreeing; it does not get to move the
        //R clock.
        register(key: event.keyIndex, probability: event.confidence,
                 at: event.hostTime, snapped: onset != nil)
    }
}

//
//  DetectionTestViewModel.swift
//  Kotek
//
//  ViewModel coordinating the practice-mode detector diagnostic pipeline.
//  Manages StrikeFusion (CoreML crop classifier), MarkerFusion (HSV reflective tracking),
//  audio onset corroboration, and live dictionary learning.
//

import FactoryKit
import SwiftUI
import Vision

@Observable
@MainActor
final class DetectionTestViewModel {
    let camera: CameraController
    let audio: AudioEngineController

    var overlaySize: CGSize = .zero
    var scores: [Int: Double] = [:]
    var markerFrame: MarkerFusion.Frame?
    var markerMisses: Int = 0
    var markerScans: Int = 0
    var bandEdges: [Double] = []
    var gateVetoed: Int = 0
    var lastGate: String?
    var markerTimingErrorMs: Double?

    var lastHit: DetectionHit?
    var log: [DetectionHit] = []

    var examples: [Int: Int] = [:]
    var agreement = KeyDecomposer.Agreement()
    var showDictionary: Bool = true
    var vetoed: Int = 0
    var peakScores: [Int: Double] = [:]

    var onsetCount: Int = 0
    var resolvedCount: Int = 0
    var lastOnsetTop: [(key: Int, score: Double)] = []
    var lastFrameAge: Double = 0

    private var fusion: StrikeFusion?
    private var markerFusion: MarkerFusion?
    private var detector = VisionStrikeDetector()
    private let visionTeachingConfidence: Double = 0.75

    init(
        camera: CameraController = Container.shared.cameraService(),
        audio: AudioEngineController = Container.shared.audioService()
    ) {
        self.camera = camera
        self.audio = audio
    }

    // MARK: - Lifecycle

    func start(app: AppState) {
        camera.start()
        if app.fixedMount {
            camera.lockFocusAndExposure()
        } else {
            camera.enableContinuousAutoFocus()
        }

        fusion = StrikeFusion(
            frames: camera.frameBuffer,
            keys: app.profile.keys,
            viewSize: overlaySize
        )
        markerFusion = MarkerFusion(
            frames: camera.frameBuffer,
            keys: app.profile.keys,
            viewSize: overlaySize
        )

        applyMarkerSettings(app: app)
        // Configure exposure/torch after focus/exposure lock above
        configureMarkerCamera(app: app)

        try? audio.start(profile: app.profile)
        if let baseline = app.profile.strikeBaseline {
            audio.setBaselineTemplate(baseline)
        }
        audio.setKeyOpinionsEnabled(true)
        audio.setDecompositionKeys([])

        audio.onStrikeDetected = { [weak self] hostTime in
            Task { @MainActor in
                guard let self else { return }
                self.onsetCount += 1
                guard app.audioTriggersStrikes, let fusion = self.fusion else { return }
                guard let probe = await fusion.scoresAt(hostTime: hostTime) else { return }
                self.lastFrameAge = probe.frameAge
                self.lastOnsetTop = probe.scores
                    .sorted { $0.value > $1.value }
                    .prefix(3)
                    .map { (key: $0.key, score: $0.value) }

                guard let best = self.lastOnsetTop.first, best.score >= app.visionThreshold else { return }
                guard await self.markerAllows(key: best.key, at: hostTime, app: app) else { return }

                self.resolvedCount += 1
                self.register(key: best.key, probability: best.score, at: hostTime, snapped: true)
            }
        }
    }

    func stop(app: AppState) {
        // Torch outlives screen if not put back
        camera.setMarkerVision(false)
        audio.onStrikeDetected = nil
        audio.learnedAtoms { templates in
            app.storeLinearTemplates(templates)
        }
        audio.setKeyOpinionsEnabled(false)
        audio.stop()
    }

    func updateOverlaySize(_ newSize: CGSize) {
        overlaySize = newSize
        Task {
            await fusion?.setViewSize(newSize)
            await markerFusion?.setViewSize(newSize)
        }
    }

    // MARK: - Pipeline Loops

    func runDetection(app: AppState) async {
        detector.reset()
        await fusion?.setMinHitProbability(Detection.namingThreshold(from: app.visionThreshold))

        while !Task.isCancelled {
            if app.markerVision {
                await stepMarker(app: app)
                try? await Task.sleep(for: .milliseconds(20))
                continue
            }

            await refreshMarkerForGate(app: app)

            if overlaySize.width > 0, let (s, hostTime) = await fusion?.latestScores() {
                scores = s
                for (k, v) in s where v > (peakScores[k] ?? 0) {
                    peakScores[k] = v
                }

                detector.apply(threshold: app.visionThreshold, relativeDip: app.visionRelativeDip)
                let fired = detector.process(scores: s, now: hostTime)

                if let key = fired.max(by: { (s[$0] ?? 0) < (s[$1] ?? 0) }) {
                    let onset = audio.nearestOnset(to: hostTime, within: Detection.corroborationWindow)
                    if app.requireStrikeSound, onset == nil {
                        vetoed += 1
                        continue
                    }

                    let strikeTime = onset ?? hostTime
                    guard await markerAllows(key: key, at: strikeTime, app: app) else { continue }
                    let probability = s[key] ?? 0

                    let heard = audio.debugOpinion(at: strikeTime)
                    var hit = DetectionHit(key: key, prob: probability, audioSnapped: onset != nil)
                    if let heard {
                        hit.heardKey = heard.best?.keyIndex
                        hit.heardShare = heard.best?.share
                        hit.residual = heard.residual
                        hit.heardTrusted = heard.isTrusted
                    }

                    register(key: key, probability: probability, at: strikeTime, snapped: onset != nil, prebuilt: hit)
                }
            }

            try? await Task.sleep(for: .milliseconds(60))
        }
    }

    func pollDictionary() async {
        while !Task.isCancelled {
            audio.decompositionProgress { [weak self] progress in
                Task { @MainActor in
                    self?.examples = progress
                }
            }
            audio.agreementStats { [weak self] stats in
                Task { @MainActor in
                    self?.agreement = stats
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    // MARK: - Marker Configuration

    func configureMarkerCamera(app: AppState) {
        camera.setMarkerVision(
            app.markerVision || app.requireMarker,
            exposureBias: app.markerVision ? app.markerExposureBias : 0
        )
    }

    func applyMarkerSettings(app: AppState) {
        Task {
            await markerFusion?.setBrightnessThreshold(Int(app.markerBrightness))
            await markerFusion?.setColour(MarkerColour(rawValue: app.markerColour) ?? .red)
            await markerFusion?.setSaturationFloor(Int(app.markerSaturationFloor))
            await markerFusion?.setROITop(app.markerROITop)
            await markerFusion?.setPOV(MarkerPOV(rawValue: app.markerPOV) ?? .top)
            await markerFusion?.setBands(
                left: app.markerBandLeft,
                right: app.markerBandRight,
                skew: app.markerBandSkew,
                flip: app.markerBandFlip
            )
            bandEdges = await markerFusion?.bandEdges() ?? []
            await markerFusion?.setMinApproachSpeed(app.markerMinSpeed)
            await markerFusion?.setTipExtension(app.markerTipExtension)
            await markerFusion?.setSaturationCeiling(Int(app.markerSaturation))
        }
    }

    func handleVisionThresholdChanged(_ new: Double) {
        Task {
            await fusion?.setMinHitProbability(Detection.namingThreshold(from: new))
        }
    }

    func handleRequireMarkerChanged(app: AppState) {
        configureMarkerCamera(app: app)
        gateVetoed = 0
        lastGate = nil
    }

    func handleMarkerVisionChanged(app: AppState) {
        configureMarkerCamera(app: app)
        markerMisses = 0
        markerScans = 0
        gateVetoed = 0
        lastGate = nil
        markerFrame = nil
        peakScores.removeAll()
        Task {
            await markerFusion?.reset()
        }
    }

    func resetPeakScores() {
        peakScores.removeAll()
    }

    // MARK: - Private Pipeline Helpers

    private func markerAllows(key: Int, at hostTime: Double, app: AppState) async -> Bool {
        guard app.requireMarker, let markerFusion else { return true }
        switch await markerFusion.gate(
            keyIndex: key,
            at: hostTime,
            margin: app.markerGateMargin,
            within: Detection.corroborationWindow
        ) {
        case .allow:
            lastGate = nil
            return true
        case .noScan:
            lastGate = "no marker scan yet"
        case let .stale(age):
            lastGate = String(format: "scan %.0f ms stale", age * 1000)
        case .noMallet:
            lastGate = "no mallet in frame"
        case let .elsewhere(other):
            lastGate = other.map { "mallet was over k\($0)" } ?? "mallet off the keys"
        }
        gateVetoed += 1
        return false
    }

    private func refreshMarkerForGate(app: AppState) async {
        guard app.requireMarker, !app.markerVision,
              let frame = await markerFusion?.poll() else { return }
        markerFrame = frame
        markerScans += 1
    }

    private func stepMarker(app: AppState) async {
        guard overlaySize.width > 0, let frame = await markerFusion?.poll() else { return }
        markerFrame = frame
        markerScans += 1
        if frame.tip == nil {
            markerMisses += 1
        } else {
            markerMisses = 0
        }
        guard let event = frame.event else { return }

        let onset = audio.nearestOnset(to: event.hostTime, within: Detection.corroborationWindow)
        if let onset {
            markerTimingErrorMs = (event.hostTime - onset) * 1000
        }
        if app.requireStrikeSound, onset == nil {
            vetoed += 1
            return
        }

        register(
            key: event.keyIndex,
            probability: event.confidence,
            at: event.hostTime,
            snapped: onset != nil
        )
    }

    private func register(
        key: Int,
        probability: Double,
        at hostTime: Double,
        snapped: Bool,
        prebuilt: DetectionHit? = nil
    ) {
        var hit = prebuilt ?? DetectionHit(key: key, prob: probability, audioSnapped: snapped)
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
        if log.count > 8 {
            log.removeFirst(log.count - 8)
        }
    }
}

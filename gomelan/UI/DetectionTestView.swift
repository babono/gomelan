//
//  DetectionTestView.swift
//  gomelan
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
    }
    @State private var lastHit: Hit?
    @State private var log: [Hit] = []

    private let hitThreshold = 0.5

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session, controller: camera)
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
            camera.enableContinuousAutoFocus()
            fusion = StrikeFusion(frames: camera.frameBuffer,
                                  keys: app.profile.keys,
                                  viewSize: overlaySize)
            try? audio.start(profile: app.profile)
            if let baseline = app.profile.strikeBaseline {
                audio.setBaselineTemplate(baseline)
            }
        }
        .onDisappear { audio.stop() }
        .task { await runDetection() }
    }

    // MARK: - Overlay

    private var keyOverlay: some View {
        GeometryReader { geometry in
            ForEach(app.profile.keys) { key in
                let prob = scores[key.index] ?? 0
                let isHit = prob >= hitThreshold
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

    // MARK: - Detection loop (identical to PlayView.runVisionDetection)

    private func runDetection() async {
        detector.reset()
        while !Task.isCancelled {
            if overlaySize.width > 0, let (s, hostTime) = await fusion?.latestScores() {
                scores = s
                let fired = detector.process(scores: s)
                if let key = fired.max(by: { (s[$0] ?? 0) < (s[$1] ?? 0) }) {
                    let snapped = audio.nearestOnset(to: hostTime, within: 0.08) != nil
                    let hit = Hit(key: key, prob: s[key] ?? 0, audioSnapped: snapped)
                    lastHit = hit
                    log.append(hit)
                    if log.count > 8 { log.removeFirst(log.count - 8) }
                }
            }
            try? await Task.sleep(for: .milliseconds(60))
        }
    }
}

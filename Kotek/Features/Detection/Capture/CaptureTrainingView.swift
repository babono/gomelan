//
//  CaptureTrainingView.swift
//  Kotek
//
//  Collect labelled crops for retraining MalletDetector, through the exact crop
//  path inference uses (see TrainingCapture).
//
//  Flow: pick the bilah you are about to work on by tapping it, pick what you
//  are demonstrating, then either strike it — every detected strike sound
//  captures a frame automatically — or tap Capture for the silent cases.
//
//  Strikes auto-capture because the frame that matters is the one where the
//  mallet is in contact, which lasts a few milliseconds. Nobody can tap a shutter
//  on that. The audio onset already knows exactly when it happened, so it picks
//  the frame instead.
//

import FactoryKit
import QuartzCore
import SwiftUI

struct CaptureTrainingView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController
    let audio: AudioEngineController

    @MainActor
    init(
        camera: CameraController = Container.shared.cameraService(),
        audio: AudioEngineController = Container.shared.audioService()
    ) {
        self.camera = camera
        self.audio = audio
    }

    @State private var capture = TrainingCapture()
    @State private var overlaySize: CGSize = .zero
    @State private var target: Int?
    @State private var intent: TrainingCapture.Intent = .strike
    @State private var counts: [String: Int] = [:]
    /// Flashes the overlay when a capture lands, so it is obvious it fired.
    @State private var flashAt: Double = 0
    @State private var exportURL: URL?
    @State private var exporting = false

    var body: some View {
        ZStack {
            CameraPreview(camera: camera, forwardsRotation: true)
                .ignoresSafeArea()

            keyOverlay

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
        .onAppear(perform: setup)
        .onDisappear(perform: teardown)
        .task { await pollCounts() }
        .sheet(item: $exportURL) { url in ShareSheet(items: [url]) }
    }

    // MARK: - Overlay

    /// Tap a bilah to make it the subject. Everything else in frame becomes a
    /// negative automatically, which is where most of the data comes from.
    private var keyOverlay: some View {
        GeometryReader { geometry in
            ForEach(app.profile.keys) { key in
                let rect = key.rect.rect(in: geometry.size)
                let isTarget = key.index == target
                let neighbour = target.map { abs($0 - key.index) == 1 } ?? false

                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isTarget ? Theme.terracotta
                            : (neighbour ? Theme.copper.opacity(0.9) : .white.opacity(0.35)),
                        lineWidth: isTarget ? 4 : (neighbour ? 2.5 : 1.5)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isTarget ? Theme.terracotta.opacity(0.22) : .clear)
                    )
                    .overlay(alignment: .top) {
                        Text(isTarget ? "\(key.index) · \(intent.title.uppercased())"
                            : (neighbour ? "\(key.index) · NEIGHBOUR" : "\(key.index)"))
                            .font(.sans(10, weight: .bold).monospacedDigit())
                            .foregroundStyle(isTarget ? Theme.terracotta
                                : (neighbour ? Theme.copper : .white.opacity(0.6)))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.black.opacity(0.65), in: Capsule())
                            .offset(y: -16)
                    }
                    // Hit-testing must be attached BEFORE `.position`, not after.
                    //
                    // `.position` does not return a small view sitting at a
                    // point — it returns a view filling ALL available space with
                    // its content placed at that point. So a `.contentShape`
                    // applied afterwards describes the whole overlay, not the
                    // bilah: every key claimed the entire screen, they stacked in
                    // ForEach order, and the last one drawn swallowed every tap.
                    // That is why this always selected key 9.
                    .frame(width: rect.width, height: rect.height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { @concurrent in
                            await KajarTick.strike()
                        }
                        target = (target == key.index) ? nil : key.index
                    }
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack {
                AppButton("Back", systemImage: "chevron.left") {
                    app.closeCaptureTraining()
                }
                Spacer()
                Text(totalLabel)
                    .font(.sans(12, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.black.opacity(0.6), in: Capsule())
            }
            .padding(.horizontal, 24).padding(.top, 20)

            HStack(alignment: .top) {
                tallyPanel
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 10)

            Spacer()

            controls
        }
    }

    private var tallyPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("CAPTURED")
                .font(.sans(10, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.copper)
            ForEach(["strike", "hover", "damp", "neighbour", "empty", "idle"], id: \.self) { prefix in
                HStack {
                    Text(prefix)
                        .font(.sans(10).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("\(counts[prefix] ?? 0)")
                        .font(.sans(11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(prefix == "strike" ? Theme.hit : .white)
                }
            }
        }
        .padding(10)
        .frame(width: 160)
        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 10))
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Text(hint)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(.black.opacity(0.6), in: Capsule())

            HStack(spacing: 10) {
                ForEach(TrainingCapture.Intent.allCases, id: \.self) { option in
                    AppChip(isSelected: intent == option) {
                        intent = option
                    } label: {
                        Text(option.title)
                    }
                }

                AppButton("Capture", systemImage: "camera.fill", prominence: .primary, action: captureNow)
                    .disabled(!canCapture)

                AppIconButton(
                    systemImage: exporting ? "hourglass" : "square.and.arrow.up",
                    label: "Export captures",
                    action: exportAll
                )
                .disabled(exporting)

                AppIconButton(systemImage: "trash", label: "Clear captures") {
                    capture.clear()
                }
            }
            .padding(.bottom, 22)
        }
    }

    private var canCapture: Bool {
        intent == .idle || target != nil
    }

    private var totalLabel: String {
        let all = counts.values.reduce(0, +)
        let hits = counts["strike"] ?? 0
        return "\(all) crops · \(hits) hit"
    }

    private var hint: String {
        if intent == .strike {
            return target == nil
                ? "Tap the key you're about to strike"
                : "Strike it — each sound captures automatically"
        }
        if intent == .idle { return "Nothing in shot · tap Capture" }
        return target == nil ? "Tap the key to demonstrate on" : "Hold the pose · tap Capture"
    }

    // MARK: - Capture

    /// Manual shutter, for the silent intents.
    private func captureNow() {
        guard let frame = camera.frameBuffer.nearest(to: CACurrentMediaTime()) else { return }
        commit(frame)
    }

    private func commit(_ frame: FrameBuffer.Frame) {
        capture.capture(
            frame: frame.image,
            frameSize: frame.size,
            keys: app.profile.keys,
            viewSize: overlaySize,
            target: intent == .idle ? nil : target,
            intent: intent
        )
        flashAt = CACurrentMediaTime()
    }

    /// Zip everything captured and offer it to AirDrop / Files.
    private func exportAll() {
        exporting = true
        capture.exportArchive { url in
            exporting = false
            exportURL = url
        }
    }

    private func pollCounts() async {
        while !Task.isCancelled {
            counts = capture.snapshotCounts()
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    // MARK: - Lifecycle

    private func setup() {
        camera.start()
        if app.fixedMount { camera.lockFocusAndExposure() } else { camera.enableContinuousAutoFocus() }
        try? audio.start(profile: app.profile)

        // Strikes are auto-captured off the audio onset: contact lasts a few
        // milliseconds and no one can tap a shutter on it, but the onset already
        // knows precisely when it happened and the frame buffer still holds it.
        audio.onStrikeDetected = { hostTime in
            Task { @MainActor in
                guard intent == .strike, target != nil,
                      let frame = camera.frameBuffer.nearest(to: hostTime) else { return }
                commit(frame)
            }
        }
    }

    private func teardown() {
        audio.onStrikeDetected = nil
        audio.stop()
    }
}

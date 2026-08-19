//
//  MalletTestView.swift
//  Kotek
//
//  Dev screen for the vision hit classifier (MalletDetector). Runs the model on
//  every calibrated key crop a few times a second and tints each key by its hit
//  probability, so we can eyeball two things before trusting fusion in play:
//    1. the crops line up with the real keys (orientation + aspect-fill mapping)
//    2. the model actually fires "hit" when a key is struck
//
//  Per-frame classification is fine here — this is a diagnostic, not the hot path.
//

import SwiftUI
import QuartzCore

struct MalletTestView: View {
    @Environment(AppState.self) private var app
    var camera: CameraController

    @State private var classifier: MalletHitClassifier?
    @State private var scores: [Int: Double] = [:]
    /// The exact crop fed to the model per key, for the debug strip below.
    @State private var crops: [Int: CGImage] = [:]
    @State private var overlaySize: CGSize = .zero

    /// Matches StrikeFusion's default so what we see here maps to play behaviour.
    private let hitThreshold = 0.5

    var body: some View {
        ZStack {
            CameraPreview(camera: camera, forwardsRotation: true)
                .ignoresSafeArea()

            // Per-key overlay tinted by hit probability.
            GeometryReader { geometry in
                ForEach(app.profile.keys) { key in
                    let prob = scores[key.index] ?? 0
                    let isHit = prob >= hitThreshold
                    let rect = key.rect.rect(in: geometry.size)

                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isHit ? Color.green : .white.opacity(0.4), lineWidth: isHit ? 3 : 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.green.opacity(isHit ? 0.35 * prob : 0))
                        )
                        .overlay(alignment: .top) {
                            Text("\(key.index) · \(Int(prob * 100))%")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(isHit ? .green : .white.opacity(0.7))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.6), in: Capsule())
                                .offset(y: -18)
                        }
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                .onAppear { overlaySize = geometry.size }
                .onChange(of: geometry.size) { _, new in overlaySize = new }
            }
            .ignoresSafeArea()

            // Top HUD.
            VStack {
                HStack(spacing: 16) {
                    SecondaryButton(title: "Back", systemImage: "chevron.left") {
                        app.closeMalletTest()
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Circle()
                            .fill(classifier != nil ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                            .shadow(color: classifier != nil ? .green : .orange, radius: 4)

                        Text(classifier != nil ? "MODEL LOADED" : "NO MODEL")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.6), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                Spacer()

                // Debug strip: the actual crop handed to the model per key. This
                // is the ground truth for "is the model seeing the right thing?"
                // — if these don't each show a single key, the mapping is off.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(app.profile.keys) { key in
                            VStack(spacing: 4) {
                                if let crop = crops[key.index] {
                                    // Natural aspect of the dragged crop, so you can
                                    // check it frames one bar (the model squashes it).
                                    Image(decorative: crop, scale: 1)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 44, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                } else {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(.white.opacity(0.1))
                                        .frame(width: 44, height: 72)
                                }
                                Text("\(key.index) · \(Int((scores[key.index] ?? 0) * 100))%")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 10)
                .background(.black.opacity(0.5))
            }
        }
        .onAppear {
            camera.start()
            // Hand focus back: the aligning flow may have left it locked/blurry.
            if app.fixedMount { camera.lockFocusAndExposure() } else { camera.enableContinuousAutoFocus() }
        }
        .task { await runClassificationLoop() }
    }

    // MARK: - Classification loop

    private func runClassificationLoop() async {
        if classifier == nil { classifier = MalletHitClassifier() }
        while !Task.isCancelled {
            classifyLatestFrame()
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func classifyLatestFrame() {
        guard let classifier,
              overlaySize.width > 0, overlaySize.height > 0,
              let frame = camera.frameBuffer.nearest(to: CACurrentMediaTime()) else { return }

        var next: [Int: Double] = [:]
        var nextCrops: [Int: CGImage] = [:]
        for key in app.profile.keys {
            let cropRect = CropMapper.bufferRect(overlay: key.rect,
                                                 bufferSize: frame.size,
                                                 viewSize: overlaySize)
            guard let crop = MalletHitClassifier.crop(frame.image, to: cropRect) else { continue }
            nextCrops[key.index] = crop
            next[key.index] = classifier.hitProbability(crop: crop)
        }
        scores = next
        crops = nextCrops
    }
}

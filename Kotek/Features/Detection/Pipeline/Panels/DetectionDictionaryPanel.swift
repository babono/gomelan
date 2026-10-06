//
//  DetectionDictionaryPanel.swift
//  Kotek
//
//  Diagnostic inspector panel for the detection test pipeline.
//  Exposes live marker tracking stats, onset timings, key dictionary atoms,
//  and threshold tuning.
//

import SwiftUI

struct DetectionDictionaryPanel: View {
    @Bindable var app: AppState
    let viewModel: DetectionTestViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header stays pinned so the collapse control is always reachable.
            HStack(spacing: 8) {
                Text("DICTIONARY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.copper)
                Spacer()
                Button {
                    viewModel.showDictionary.toggle()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.kajar)
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    markerSection

                    if !app.markerVision {
                        markerGateSection
                    }

                    Divider().overlay(Color.white.opacity(0.2))

                    onsetPathSection

                    dictionaryAtomsSection

                    agreementSection

                    thresholdTuningSection

                    strikeTriggerSection

                    disagreementSection
                }
            }
            .frame(maxHeight: panelContentHeight)
        }
        .padding(12)
        .frame(width: 210, alignment: .leading)
        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Sections

    @ViewBuilder
    private var markerSection: some View {
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
            HStack(spacing: 4) {
                ForEach(MarkerColour.allCases, id: \.rawValue) { c in
                    Button {
                        app.markerColour = c.rawValue
                    } label: {
                        Text(c.name)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(app.markerColour == c.rawValue ? Theme.ink : .white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(app.markerColour == c.rawValue ? Theme.copper : .white.opacity(0.15),
                                        in: Capsule())
                    }
                    .buttonStyle(.kajar)
                }
            }
            Text(MarkerColour(rawValue: app.markerColour)?.note ?? "")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                ForEach(MarkerPOV.allCases, id: \.rawValue) { p in
                    Button {
                        app.markerPOV = p.rawValue
                    } label: {
                        Text(p.name)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(app.markerPOV == p.rawValue ? Theme.ink : .white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(app.markerPOV == p.rawValue ? Theme.accent : .white.opacity(0.15),
                                        in: Capsule())
                    }
                    .buttonStyle(.kajar)
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

            let lit = (viewModel.markerFrame?.litFraction ?? 0) * 100
            statRow("scans", "\(viewModel.markerScans)")
            statRow("blobs", "\(viewModel.markerFrame?.blobs.count ?? 0)")
            statRow("lit", String(format: "%.2f %%", lit))
            statRow("lost frames", "\(viewModel.markerMisses)")

            if let f = viewModel.markerFrame {
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

            if let err = viewModel.markerTimingErrorMs {
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
            tuningRow("tip reach", value: $app.markerTipExtension, range: 0...1, step: 0.05,
                      display: String(format: "%.2f", app.markerTipExtension))
        }
    }

    @ViewBuilder
    private var markerGateSection: some View {
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
            statRow("gate vetoed", "\(viewModel.gateVetoed)")
            if let lastGate = viewModel.lastGate {
                Text(lastGate)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.wrong)
                    .fixedSize(horizontal: false, vertical: true)
            }
            tuningRow("gate margin", value: $app.markerGateMargin, range: 0...0.3, step: 0.01,
                      display: String(format: "%.2f", app.markerGateMargin))
        }
    }

    @ViewBuilder
    private var onsetPathSection: some View {
        Text("ONSET PATH")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(Theme.wrong)

        statRow("model", MalletHitClassifier.loaded ? "loaded" : "FAILED")

        HStack(spacing: 4) {
            ForEach(Array(MalletHitClassifier.cropScaleOptions.enumerated()), id: \.offset) { i, mode in
                Button {
                    app.cropScaleMode = i
                    MalletHitClassifier.applyCropScale(mode: i)
                    viewModel.resetPeakScores()
                } label: {
                    Text(mode.name)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(app.cropScaleMode == i ? Theme.ink : .white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(app.cropScaleMode == i ? Theme.copper : .white.opacity(0.15),
                                    in: Capsule())
                }
                .buttonStyle(.kajar)
            }
        }
        if let failure = MalletHitClassifier.lastFailure {
            Text(failure)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.wrong)
                .fixedSize(horizontal: false, vertical: true)
        }
        statRow("audio onsets", "\(viewModel.onsetCount)")
        statRow("resolved", "\(viewModel.resolvedCount)")
        statRow("frame age", String(format: "%.0f ms", viewModel.lastFrameAge * 1000))
        if !viewModel.lastOnsetTop.isEmpty {
            Text("at last onset:")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
            ForEach(viewModel.lastOnsetTop, id: \.key) { entry in
                Text(String(format: "   k%02d  %.2f", entry.key, entry.score))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(entry.score >= app.visionThreshold ? Theme.hit : Theme.wrong)
            }
        }
    }

    @ViewBuilder
    private var dictionaryAtomsSection: some View {
        Divider().overlay(Color.white.opacity(0.2))

        VStack(alignment: .leading, spacing: 3) {
            ForEach(app.profile.keys) { key in
                let count = viewModel.examples[key.index] ?? 0
                let trusted = count >= KeyDecomposer.strikesToTrustAtom
                HStack(spacing: 6) {
                    Text(String(format: "%2d", key.index))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
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
    }

    @ViewBuilder
    private var agreementSection: some View {
        Divider().overlay(Color.white.opacity(0.2))

        let decided = viewModel.agreement.agreed + viewModel.agreement.disagreed
        statRow("agree", decided > 0
                ? "\(viewModel.agreement.agreed)/\(decided)  \(Int(viewModel.agreement.agreementRate * 100))%"
                : "—")
        statRow("recovered", "\(viewModel.agreement.recovered)")
        statRow("no opinion", "\(viewModel.agreement.noOpinion)")
        statRow("quarantined", "\(viewModel.agreement.quarantined)")
        statRow("silent-vetoed", "\(viewModel.vetoed)")
    }

    @ViewBuilder
    private var thresholdTuningSection: some View {
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

            HStack {
                Text("peak seen")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(viewModel.peakScores.values.max().map { String(format: "%.2f", $0) } ?? "—")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.hit)
                Button {
                    viewModel.resetPeakScores()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.kajar)
            }
        }
    }

    @ViewBuilder
    private var strikeTriggerSection: some View {
        Toggle(isOn: $app.audioTriggersStrikes) {
            Text("audio triggers")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
        }
        .toggleStyle(.switch)
        .tint(Theme.copper)
        .scaleEffect(0.75, anchor: .leading)
        .frame(height: 22)

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
    }

    @ViewBuilder
    private var disagreementSection: some View {
        if !viewModel.agreement.recent.isEmpty {
            Divider().overlay(Color.white.opacity(0.2))
            Text("EYE ≠ EAR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.wrong)
            ForEach(Array(viewModel.agreement.recent.suffix(4).enumerated()), id: \.offset) { _, d in
                Text("saw \(d.visionKey) (\(Int(d.visionConfidence * 100))%) · heard \(d.heardKey) (\(Int(d.heardShare * 100))%)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    // MARK: - Helpers

    private var panelContentHeight: CGFloat {
        guard viewModel.overlaySize.height > 0 else { return 200 }
        return min(300, max(120, viewModel.overlaySize.height - 150))
    }

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
}

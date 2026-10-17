//
//  AligningControlsBar.swift
//  Kotek
//
//  Bottom controls and adjustment toolbars for the aligning calibration step.
//

import SwiftUI

/// Bottom toolbar with detection status, reset affordance, spanner toggle,
/// auto-detect trigger, and next transition button.
struct AligningBottomBar: View {
    @Bindable var viewModel: AligningViewModel

    var body: some View {
        HStack(spacing: 14) {
            if viewModel.detecting {
                ProgressView().tint(Theme.copper)
            }

            Text(viewModel.status)
                .font(.sans(13))
                .foregroundStyle(Theme.inkStone)
                .lineLimit(1)

            Spacer()

            AppButton("Reset fit") {
                viewModel.resetFit()
            }

            // Spanner: reveal/hide the row-level fit controls.
            AppIconButton(
                systemImage: "wrench.adjustable",
                label: "Fine-tune the fit",
                prominence: viewModel.showAdjust ? .primary : .standard
            ) {
                withAnimation(.snappy(duration: 0.2)) {
                    viewModel.showAdjust.toggle()
                }
            }

            AppButton(
                "Auto-detect"
            ) {
                Task { await viewModel.autoDetect() }
            }
            .disabled(viewModel.detecting)

            AppButton(
                "Next",
                prominence: .primary
            ) {
                viewModel.confirmAlignment()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: [.bottom, .horizontal])
        )
    }
}

/// Row-level adjustment toolbar (width, height, spacing, vertical nudge)
/// toggled via the spanner button.
struct AligningAdjustBar: View {
    @Bindable var viewModel: AligningViewModel

    var body: some View {
        HStack(spacing: Theme.controlSpacing) {
            adjustGroup(
                "Width",
                { viewModel.adjustWidth(-0.004) },
                { viewModel.adjustWidth(0.004) }
            )
            adjustGroup(
                "Height",
                { viewModel.adjustHeight(-0.008) },
                { viewModel.adjustHeight(0.008) }
            )
            adjustGroup(
                "Spacing",
                { viewModel.adjustSpacing(0.97) },
                { viewModel.adjustSpacing(1.03) }
            )
            adjustGroup(
                "Row",
                { viewModel.nudgeRow(-0.01) },
                { viewModel.nudgeRow(0.01) }
            )
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(
            Color.black.opacity(0.5).ignoresSafeArea(edges: .horizontal)
        )
    }

    private func adjustGroup(
        _ label: String,
        _ minus: @escaping () -> Void,
        _ plus: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Theme.controlSpacing) {
            Text(label)
                .font(.sans(10, weight: .semibold)).textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(Theme.inkStone)
            AppIconButton(systemImage: "minus", label: "Decrease \(label.lowercased())", action: minus)
            AppIconButton(systemImage: "plus", label: "Increase \(label.lowercased())", action: plus)
        }
    }
}

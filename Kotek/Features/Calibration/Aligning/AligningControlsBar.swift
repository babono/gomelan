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

            Button("Reset fit") {
                viewModel.resetFit()
            }
            .font(.sans(13, weight: .medium))
            .foregroundStyle(Theme.inkStone)
            .underline()
            .buttonStyle(.kajar)

            // Spanner: reveal/hide the row-level fit controls.
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    viewModel.showAdjust.toggle()
                }
            } label: {
                Image(systemName: "wrench.adjustable")
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(
                        viewModel.showAdjust ? Theme.ink : Theme.copper
                    )
                    .frame(width: 38, height: 38)
                    .background(
                        viewModel.showAdjust ? Theme.copper : .clear,
                        in: Circle()
                    )
                    .overlay(
                        Circle().strokeBorder(
                            Theme.copper.opacity(0.6),
                            lineWidth: 1.5
                        )
                    )
            }
            .buttonStyle(.kajar)

            PillButton(
                title: "Auto-detect",
                style: .outlined,
                tint: Theme.copper,
                compact: true
            ) {
                Task { await viewModel.autoDetect() }
            }
            .disabled(viewModel.detecting)

            PillButton(
                title: "Next",
                trailingSystemImage: "arrow.right",
                style: .filled,
                tint: Theme.copper,
                compact: true
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
        HStack(spacing: 14) {
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
        HStack(spacing: 5) {
            Text(label)
                .font(.sans(10, weight: .semibold)).textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(Theme.inkStone)
            adjustButton("minus", minus)
            adjustButton("plus", plus)
        }
    }

    private func adjustButton(
        _ system: String,
        _ action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.sans(11, weight: .semibold))
                .foregroundStyle(Theme.copper)
                .frame(width: 26, height: 26)
                .overlay(
                    Circle().strokeBorder(
                        Theme.copper.opacity(0.6),
                        lineWidth: 1.5
                    )
                )
        }
        .buttonStyle(.kajar)
    }
}

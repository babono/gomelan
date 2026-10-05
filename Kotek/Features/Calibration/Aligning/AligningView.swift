//
//  AligningView.swift
//  Kotek
//
//  Setup step 3/4 (PRD §13.4 .aligning). The bundled bilah masks are overlaid
//  and draggable — the carved, gilded frame is visually busy, so manual
//  drag-adjust is not optional polish (§3.2). Confirming locks focus/exposure
//  (§6.2) and leads into the baseline.
//

import FactoryKit
import SwiftUI

struct AligningView: View {
    @State var viewModel: AligningViewModel = AligningViewModel(
        cameraService: Container.shared.cameraService()
    )

    var body: some View {
        ZStack {
            // Full-bleed camera fills the whole screen.
            CameraPreview(camera: viewModel.camera)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.22).ignoresSafeArea())

            // Masks + loupe live in the same full-bleed coordinate space as the
            // camera, so normalised rects map straight onto what's shown.
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewModel.overlaySize = geo.size }
                    .onChange(of: geo.size) { _, new in
                        viewModel.overlaySize = new
                    }

                ForEach(viewModel.keys.indices, id: \.self) { i in
                    if viewModel.selectedIndex != i {
                        keyMask(for: i, in: geo.size)
                    }
                }

                // Render selected key on top so its stroke and handles are never obscured
                if let selected = viewModel.selectedIndex,
                    viewModel.keys.indices.contains(selected)
                {
                    keyMask(for: selected, in: geo.size)
                }

                // Magnifier — only while resizing, at the corner being pulled.
                if let focus = viewModel.dragFocus,
                    let frame = viewModel.camera.frameBuffer.nearest(
                        to: CACurrentMediaTime()
                    )
                {
                    MagnifierLoupeView(
                        focus: focus,
                        image: frame.image,
                        bufferSize: frame.size,
                        viewSize: geo.size
                    )
                    .position(
                        x: min(
                            max(focus.x * geo.size.width, 92),
                            geo.size.width - 92
                        ),
                        y: 96
                    )
                    .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()

            //R Chrome floats on top, inset from the notch — but its SCRIMS are
            //R not. A gradient that stops where the safe area does leaves the
            //R feed lit in the two corners it was drawn to darken, which on a
            //R landscape phone is a 59pt band down each side. The controls stay
            //R inset; the scrims behind them run to the glass.
            VStack(spacing: 0) {
                TopBar(
                    title: "Fit the mask to your keys",
                    backTitle: "Rescan",
                    onBack: { viewModel.app.screen = .framing },
                    trailingText: "3 / 4",
                    tint: Theme.cream,
                    accent: Theme.copper,
                    compact: true
                )
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.5), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: [.top, .horizontal])
                )
                Spacer()
                if viewModel.showAdjust { adjustBar }
                bottomBar
            }
        }
        .busy(viewModel.busyMessage)
        .onAppear {
            viewModel.camera.start()
            viewModel.setup()
        }
    }

    private func keyMask(for i: Int, in size: CGSize) -> some View {
        RectMaskView(
            rect: viewModel.rectBinding(i),
            viewSize: size,
            label: bilahLabel(
                viewModel.keys[i].index,
                count: viewModel.keys.count
            ),
            isSelected: viewModel.selectedIndex == i,
            onSelect: { viewModel.selectedIndex = i },
            onResizeFocus: { viewModel.dragFocus = $0 }
        )
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            if viewModel.detecting { ProgressView().tint(Theme.copper) }
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
    
    private var adjustBar: some View {
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
            adjustGroup("Row", { viewModel.nudgeRow(-0.01) }, { viewModel.nudgeRow(0.01) })
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        //R Horizontal only: this strip sits BETWEEN the masks and the caption
        //R bar, so it has a bottom edge that is meant to be seen.
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

    private func adjustButton(_ system: String, _ action: @escaping () -> Void)
        -> some View
    {
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

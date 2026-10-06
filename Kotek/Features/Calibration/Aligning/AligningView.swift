//
//  AligningView.swift
//  Kotek
//
//  Setup step 3/4 (PRD §3.2, §13.4 .aligning).
//  The bundled bilah masks are overlaid and draggable onto the live camera.
//  Confirming locks focus/exposure (§6.2) and leads into the acoustic baseline.
//

import FactoryKit
import SwiftUI

struct AligningView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController

    init(camera: CameraController = Container.shared.cameraService()) {
        self.camera = camera
    }

    var body: some View {
        AligningContentView(app: app, camera: camera)
    }
}

private struct AligningContentView: View {
    let app: AppState
    let camera: CameraController
    @State private var viewModel: AligningViewModel

    init(app: AppState, camera: CameraController) {
        self.app = app
        self.camera = camera
        _viewModel = State(wrappedValue: AligningViewModel(app: app, camera: camera))
    }

    var body: some View {
        @Bindable var vm = viewModel

        ZStack {
            // Full-bleed camera fills the whole screen.
            CameraPreview(camera: vm.camera)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.22).ignoresSafeArea())

            // Masks + loupe live in the same full-bleed coordinate space as the camera.
            GeometryReader { geo in
                Color.clear
                    .onAppear { vm.overlaySize = geo.size }
                    .onChange(of: geo.size) { _, new in
                        vm.overlaySize = new
                    }

                ForEach(vm.keys.indices, id: \.self) { i in
                    if vm.selectedIndex != i {
                        keyMask(for: i, in: geo.size, vm: $vm)
                    }
                }

                // Render selected key on top so its stroke and handles are never obscured
                if let selected = vm.selectedIndex,
                    vm.keys.indices.contains(selected)
                {
                    keyMask(for: selected, in: geo.size, vm: $vm)
                }

                // Magnifier — only while resizing, at the corner being pulled.
                if let focus = vm.dragFocus,
                    let frame = vm.camera.frameBuffer.nearest(to: CACurrentMediaTime())
                {
                    MagnifierLoupeView(
                        focus: focus,
                        image: frame.image,
                        bufferSize: frame.size,
                        viewSize: geo.size
                    )
                    .position(
                        x: min(max(focus.x * geo.size.width, 92), geo.size.width - 92),
                        y: 96
                    )
                    .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()

            // Header, adjust toolbar and bottom action bar.
            VStack(spacing: 0) {
                TopBar(
                    title: "Fit the mask to your keys",
                    backTitle: "Rescan",
                    onBack: { app.screen = .framing },
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

                if vm.showAdjust {
                    AligningAdjustBar(viewModel: vm)
                }

                AligningBottomBar(viewModel: vm)
            }
        }
        .busy(vm.busyMessage)
        .onAppear {
            vm.camera.start()
            vm.setup()
        }
    }

    private func keyMask(
        for i: Int,
        in size: CGSize,
        vm: Bindable<AligningViewModel>
    ) -> some View {
        RectMaskView(
            rect: vm.keys[i].rect,
            viewSize: size,
            label: bilahLabel(
                vm.keys[i].wrappedValue.index,
                count: vm.keys.wrappedValue.count
            ),
            isSelected: vm.selectedIndex.wrappedValue == i,
            onSelect: { vm.selectedIndex.wrappedValue = i },
            onResizeFocus: { vm.dragFocus.wrappedValue = $0 }
        )
    }
}

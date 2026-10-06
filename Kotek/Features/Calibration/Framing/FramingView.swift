//
//  FramingView.swift
//  Kotek
//
//  Setup step 2/4 (PRD §3.2, §8). Mount the phone above the gangsa and settle
//  the stand until the bilah sit roughly under the guide. Rough is the point:
//  step 3/4 is where the masks are fitted exactly.
//

import FactoryKit
import SwiftUI

struct FramingView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        FramingContentView(app: app)
    }
}

private struct FramingContentView: View {
    let app: AppState
    @State private var viewModel: FramingViewModel

    init(app: AppState, camera: CameraController = Container.shared.cameraService()) {
        self.app = app
        _viewModel = State(wrappedValue: FramingViewModel(app: app, camera: camera))
    }

    var body: some View {
        ZStack {
            CameraPreview(camera: viewModel.camera)
                .ignoresSafeArea()
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    viewModel.bleed = $0
                }

            FramingRegionView(region: viewModel.region)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TopBar(
                    title: "Frame the gangsa",
                    backTitle: "Back",
                    onBack: { app.screen = .choosingKeyCount },
                    trailingText: "2 / 4",
                    tint: Theme.cream,
                    accent: Theme.copper,
                    compact: true
                )
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.55), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: [.top, .horizontal])
                )
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: {
                    viewModel.headerBottom = $0
                }

                Spacer()

                FramingBottomBar(cameraReady: viewModel.cameraReady) {
                    viewModel.confirmFraming()
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                    viewModel.captionTop = $0
                }
            }
        }
        .background(Theme.ink)
        .onChange(of: viewModel.region) { _, _ in
            viewModel.updateFramedRegion()
        }
        .busy(viewModel.busyMessage)
        .onAppear {
            viewModel.setup()
        }
        .task {
            await viewModel.waitForCamera()
        }
    }
}

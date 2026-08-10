//
//  AligningView.swift
//  gomelan
//
//  Alignment step (PRD §13.4 .aligning). The bundled key rects are overlaid and
//  draggable — the carved, gilded frame is visually busy, so manual drag-adjust
//  is not optional polish (§3.2). Confirming locks focus/exposure (§6.2).
//

import SwiftUI

struct AligningView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController

    @State private var keys: [InstrumentKey] = []

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            GeometryReader { geo in
                ForEach(keys.indices, id: \.self) { i in
                    DraggableKey(rect: binding(for: i), viewSize: geo.size, index: keys[i].index)
                }
            }
            .ignoresSafeArea()

            VStack {
                HStack(alignment: .center) {
                    Spacer()
                        .frame(width: 80)

                    Spacer()

                    Text("Drag each key outline onto the real key")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 18)
                        .background(.black.opacity(0.55), in: Capsule())

                    Spacer()

                    Button {
                        confirmAlignment()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Done")
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.black)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 16)

                Spacer()

                // Key width & height adjustment toolbar
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Text("Width:")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Button {
                            adjustAllKeyWidths(by: -0.005)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }
                        Button {
                            adjustAllKeyWidths(by: 0.005)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }
                    }

                    Divider()
                        .frame(height: 20)
                        .background(.white.opacity(0.4))

                    HStack(spacing: 8) {
                        Text("Height:")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Button {
                            adjustAllKeyHeights(by: -0.01)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }
                        Button {
                            adjustAllKeyHeights(by: 0.01)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(.black.opacity(0.65), in: Capsule())
                .padding(.bottom, 20)
            }
            .padding()
        }
        .onAppear {
            camera.start()
            if keys.isEmpty { keys = app.profile.keys }
        }
    }

    private func confirmAlignment() {
        var profile = app.profile
        profile.keys = keys
        app.profile = profile
        app.saveProfile()
        camera.lockFocusAndExposure()
        app.alignmentConfirmed()
    }

    private func binding(for index: Int) -> Binding<NormalizedRect> {
        Binding(
            get: { keys[index].rect },
            set: { keys[index].rect = $0 }
        )
    }

    private func adjustAllKeyWidths(by delta: Double) {
        for i in keys.indices {
            let newW = max(0.02, min(0.2, keys[i].rect.w + delta))
            keys[i].rect.w = newW
        }
    }

    private func adjustAllKeyHeights(by delta: Double) {
        for i in keys.indices {
            let newH = max(0.1, min(0.8, keys[i].rect.h + delta))
            keys[i].rect.h = newH
        }
    }
}

/// A single draggable key outline. Translation is converted to normalised space
/// so the stored rect stays resolution-independent.
private struct DraggableKey: View {
    @Binding var rect: NormalizedRect
    let viewSize: CGSize
    let index: Int

    @State private var dragStart: NormalizedRect?

    var body: some View {
        let frame = rect.rect(in: viewSize)
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                .stroke(Theme.accent, lineWidth: Theme.keyOutlineWidth)
                .background(
                    RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                        .fill(Theme.accent.opacity(0.12))
                )
                .overlay(
                    Text("\(index)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                )

            // Resize handle on bottom-right corner
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(Theme.accent, in: Circle())
                .offset(x: 4, y: 4)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard viewSize.width > 0, viewSize.height > 0 else { return }
                            let newW = max(0.02, rect.w + value.translation.width / viewSize.width)
                            let newH = max(0.05, rect.h + value.translation.height / viewSize.height)
                            rect.w = newW
                            rect.h = newH
                        }
                )
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if dragStart == nil { dragStart = rect }
                    guard let start = dragStart, viewSize.width > 0, viewSize.height > 0 else { return }
                    rect = NormalizedRect(
                        x: start.x + value.translation.width / viewSize.width,
                        y: start.y + value.translation.height / viewSize.height,
                        w: start.w,
                        h: start.h
                    )
                }
                .onEnded { _ in dragStart = nil }
        )
    }
}

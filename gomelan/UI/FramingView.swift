//
//  FramingView.swift
//  gomelan
//
//  Framing step (PRD §3.2, §8). The user adjusts the stand until all keys sit
//  inside the guide outline. First-run setup is meant to take ~15 seconds (§2).
//

import SwiftUI

struct FramingView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            // Framing guide: keep all keys inside, ~10% margin each side (§3.2).
            GeometryReader { geo in
                let inset = geo.size.width * 0.1
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(.horizontal, inset)
                    .padding(.vertical, geo.size.height * 0.18)
            }
            .ignoresSafeArea()

            VStack {
                Text("Mount the phone above the gangsa and fit all keys inside the frame")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.top, 20)

                Spacer()

                PrimaryButton(title: "Keys are inside the frame", systemImage: "checkmark") {
                    app.framingConfirmed()
                }
                .frame(maxWidth: 420)
                .padding(.bottom, 28)
            }
            .padding()
        }
        .onAppear { camera.start() }
    }
}

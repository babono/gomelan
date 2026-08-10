//
//  MalletTestView.swift
//  gomelan
//
//  Test screen for real-time mallet tracking and camera detection feedback.
//

import SwiftUI

struct MalletTestView: View {
    @Environment(AppState.self) private var app
    var camera: CameraController

    var body: some View {
        ZStack {
            // Live Camera Feed
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            // Reticle & Target Overlay
            GeometryReader { geometry in
                if let mallet = camera.latestMallet {
                    // Estimate normalized point (assuming standard aspect ratio)
                    let targetX = min(max(mallet.position.x * 2.5, 40), geometry.size.width - 40)
                    let targetY = min(max(mallet.position.y * 2.5, 40), geometry.size.height - 40)

                    ZStack {
                        // Pulsing outer ring
                        Circle()
                            .stroke(Theme.accent, lineWidth: 2)
                            .frame(width: 56, height: 56)
                            .shadow(color: Theme.accent.opacity(0.8), radius: 10)

                        // Center reticle dot
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 16, height: 16)

                        // Coordinate badge above reticle
                        VStack(spacing: 2) {
                            Text("MALLET")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.accent)
                            Text("X: \(Int(mallet.position.x))  Y: \(Int(mallet.position.y))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                        .offset(y: -44)
                    }
                    .position(x: targetX, y: targetY)
                    .animation(.spring(response: 0.15, dampingFraction: 0.7), value: mallet.position)
                }
            }

            // Top HUD Control Bar
            VStack {
                HStack(spacing: 16) {
                    SecondaryButton(title: "Back", systemImage: "chevron.left") {
                        app.closeMalletTest()
                    }

                    Spacer()

                    // Status Indicator Badge
                    HStack(spacing: 8) {
                        Circle()
                            .fill(camera.latestMallet != nil ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                            .shadow(color: camera.latestMallet != nil ? .green : .orange, radius: 4)

                        Text(camera.latestMallet != nil ? "MALLET TRACKED" : "SEARCHING FOR MOTION")
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

                // Bottom Stats Panel
                if let mallet = camera.latestMallet {
                    HStack(spacing: 24) {
                        statItem(label: "X POS", value: "\(Int(mallet.position.x)) px")
                        statItem(label: "Y POS", value: "\(Int(mallet.position.y)) px")
                        statItem(label: "STATUS", value: "Active")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.1), lineWidth: 1))
                    .padding(.bottom, 24)
                }
            }
        }
        .onAppear {
            camera.start()
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)
        }
    }
}

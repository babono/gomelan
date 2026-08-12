//
//  KeyCountView.swift
//  gomelan
//
//  How many keys does this instrument have? Asked before alignment, because the
//  answer decides how many outlines there are to drag.
//
//  A gangsa pemade or kantilan normally has 10, but practice sets and partial
//  instruments are common — and during testing a smaller count is far quicker to
//  calibrate. So this is a question, not a constant.
//

import SwiftUI

struct KeyCountView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController

    @State private var count: Int = 10

    private let range = 1...14

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            Color.black.opacity(0.55).ignoresSafeArea()

            // Live preview of the layout they are choosing.
            GeometryReader { geo in
                ForEach(InstrumentProfile.layout(count: count)) { key in
                    let frame = key.rect.rect(in: geo.size)
                    RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                        .stroke(Theme.accent, lineWidth: Theme.keyOutlineWidth)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                                .fill(Theme.accent.opacity(0.12))
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.2), value: count)

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 10) {
                    Text("How many keys?")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Count the keys on your instrument")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }

                HStack(spacing: 28) {
                    stepButton(systemName: "minus", enabled: count > range.lowerBound) {
                        count = max(range.lowerBound, count - 1)
                    }

                    Text("\(count)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 110)
                        .contentTransition(.numericText())

                    stepButton(systemName: "plus", enabled: count < range.upperBound) {
                        count = min(range.upperBound, count + 1)
                    }
                }

                Text(count == 10 ? "Standard gangsa" : " ")
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)

                Button {
                    app.keyCountChosen(count)
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)

                Text("You'll position them next, then play each one once")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 24)
            }
            .padding()
        }
        .onAppear {
            camera.start()
            // Start from whatever the profile already has, so coming back here
            // does not silently reset a count the user already picked.
            if app.profile.keyCount >= range.lowerBound {
                count = min(range.upperBound, app.profile.keyCount)
            }
        }
    }

    private func stepButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title.weight(.bold))
                .foregroundStyle(enabled ? .white : .white.opacity(0.25))
                .frame(width: 62, height: 62)
                .background(.white.opacity(enabled ? 0.18 : 0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

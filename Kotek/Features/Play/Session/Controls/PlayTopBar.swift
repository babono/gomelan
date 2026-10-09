//
//  PlayTopBar.swift
//  Kotek
//
//  Top chrome for the practice screen with title, session counters, panel toggle, and pause.
//

import SwiftUI

struct PlayTopBar: View {
    let title: String
    let engine: PlayEngine
    let record: Double?
    @Binding var bottomBarVisible: Bool
    let onPause: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.sans(13, weight: .semibold))
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(Theme.copper)

            Spacer()

            // Its own view so the clock ticking doesn't re-evaluate the whole
            // screen sixty times a second just to move a counter.
            SessionCountersView(engine: engine, record: record)

            Spacer()

            // Bring the score and controls up. Down by default.
            Button {
                bottomBarVisible.toggle()
            } label: {
                Image(
                    systemName: bottomBarVisible
                        ? "rectangle.bottomthird.inset.filled" : "rectangle"
                )
                .font(.sans(15, weight: .medium))
                .foregroundStyle(
                    bottomBarVisible ? Theme.ink : Theme.copper
                )
                .frame(width: 40, height: 34)
                .background(
                    bottomBarVisible ? Theme.copper : .clear,
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        Theme.copper.opacity(0.6),
                        lineWidth: 1.5
                    )
                )
            }
            .buttonStyle(.kajar)
            .accessibilityLabel(
                bottomBarVisible ? "Hide the score" : "Show the score"
            )
            .coachTarget(.panelToggle)
            .padding(.trailing, 10)

            Button {
                onPause()
            } label: {
                Image(systemName: "pause.fill")
                    .font(.symbol(14, weight: .semibold))
                    .foregroundStyle(Theme.cream)
                    .frame(width: 40, height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                Theme.cream.opacity(0.45),
                                lineWidth: 1
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.kajar)
            .accessibilityLabel("Pause")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .coachTarget(.session)
    }
}

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
        GlassEffectContainer {
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

                ControllerStatusChip(compact: true)
                    .padding(.trailing, 10)

                // Bring the score and controls up. Down by default.
                // Lit (gold glass) while the bar is showing, as the copper fill was.
                AppIconButton(
                    systemImage: bottomBarVisible
                        ? "rectangle.bottomthird.inset.filled" : "rectangle",
                    label: engine.judging
                        ? (bottomBarVisible ? "Hide the score" : "Show the score")
                        : (bottomBarVisible ? "Hide the controls" : "Show the controls"),
                    prominence: bottomBarVisible ? .primary : .secondary,
                    size: .compact
                ) {
                    bottomBarVisible.toggle()
                }
                .coachTarget(.panelToggle)
                .padding(.trailing, 10)

                AppIconButton(systemImage: "pause.fill", label: "Pause", size: .compact) {
                    onPause()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .coachTarget(.session)
    }
}

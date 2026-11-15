//
//  LearnView.swift
//  Kotek
//
//  Learn's screens. Watch is coop's stage with the two halves for players;
//  every other step is the waterfall, set up for that step
//  (`WaterfallPlayViewModel.lesson`). Each step gets a fresh screen, so a
//  step starts from its own beginning rather than reconfiguring a clock that
//  is already running.
//

import SwiftUI

struct LearnView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        switch app.learnStage {
        case .watch:
            LearnWatchView(app: app)
        case let stage?:
            WaterfallPlayView()
                .id(stage)
        case nil:
            Color.clear
        }
    }
}

/// Both halves going round, side by side, until you have seen enough.
private struct LearnWatchView: View {
    let app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm: CoopPlayViewModel

    init(app: AppState) {
        self.app = app
        _vm = State(wrappedValue: CoopPlayViewModel(app: app, watching: true))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                AppIconButton(systemImage: "chevron.left", label: "Back to the patterns", size: .compact) {
                    vm.teardown()
                    app.exitLearn()
                }
                LearnStrip(stage: .watch)
                Spacer(minLength: 0)
                if LearnProgress.learnedAny {
                    AppButton(title: "Free play", size: .compact) {
                        vm.teardown()
                        app.skipLearn()
                    }
                    .fixedSize()
                }
                AppButton(title: "Next", trailingSystemImage: "chevron.right", prominence: .primary, size: .compact) {
                    vm.teardown()
                    app.advanceLearn()
                }
                .fixedSize()
            }
            .frame(height: 50)
            .padding(.horizontal, 24)
            .padding(.vertical, 6)

            CoopStage(lanes: vm.lanes, voicedKeys: vm.voicedKeys, damp: app.dampGuide)
                // Kipli says what the caption under the strip used to, parked
                // at the stage's top-left under the Polos / Sangsih pills, as
                // he sits on the waterfall. He flew about the stage's top for
                // a while (`.flying`, Nov 2026) so he read as a guide over the
                // layout rather than part of it, but players found a Kipli
                // wandering about with nothing to say distracting: he stays
                // in one safe corner now. Before that he sat in the header
                // beside the strip.
                .overlay(alignment: .topLeading) {
                    KipliGuide(
                        message: "Polos on the left, sangsih on the right. Next when you have the shape of it.",
                        style: .quiet
                    )
                    .padding(.leading, 24)
                    .padding(.top, CoopStage.laneHeader + 8)
                }
        }
        .background(Theme.ground.ignoresSafeArea())
        .onAppear(perform: vm.setup)
        .onDisappear(perform: vm.teardown)
        // Nothing to lose by pausing a demo, and its sound should not carry on
        // in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { vm.resume() } else { vm.pause() }
        }
    }
}

/// Watch › Polos › Sangsih › Free play, the current one lit, and the step
/// within it after a dot beside it.
struct LearnStrip: View {
    let stage: LearnStage

    private static let parts: [LocalizedStringResource] = ["Watch", "Polos", "Sangsih", "Free play"]

    private var current: Int {
        switch stage.half {
        case nil: 0
        case .polos: 1
        case .sangsih: 2
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.parts.indices, id: \.self) { i in
                if i > 0 {
                    Image(systemName: "chevron.right")
                        .font(.symbol(9, weight: .semibold))
                        .foregroundStyle(Theme.cream.opacity(0.3))
                }
                Text(Self.parts[i])
                    .font(.sans(13, weight: i == current ? .semibold : .regular))
                    .foregroundStyle(i == current ? Theme.goldText : Theme.cream.opacity(i < current ? 0.6 : 0.35))
                // Beside its half: at the end of the strip it read as a step
                // of free play.
                if i == current, stage.half != nil {
                    Text("· \(stage.title)")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.cream)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Learn, \(String(localized: Self.parts[current])), \(stage.title)")
    }
}

/// Build up's climb, Slow › Steady › Full speed › Faster: the speeds behind
/// you ticked, the one you are on lit, the ones to come faint. It replaced
/// the speed as a number in the caption ("0.5× · pass 2 of 2"), which said
/// where you were but not how far there was to go.
struct BuildUpStepper: View {
    let step: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LearnStage.buildUpNames.indices, id: \.self) { i in
                HStack(spacing: 4) {
                    if i < step {
                        Image(systemName: "checkmark")
                            .font(.symbol(10, weight: .bold))
                    }
                    Text(LearnStage.buildUpNames[i])
                }
                .font(.sans(13, weight: i == step ? .semibold : .medium))
                .foregroundStyle(
                    i == step ? Theme.surface : Theme.cream.opacity(i < step ? 0.75 : 0.35)
                )
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background {
                    if i == step {
                        Capsule().fill(Theme.primary)
                    }
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(3)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1.5))
        .animation(.easeInOut(duration: 0.3), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Speed: \(String(localized: LearnStage.buildUpNames[min(step, LearnStage.buildUpNames.count - 1)])), \(step + 1) of \(LearnStage.buildUpNames.count)"
        )
    }
}

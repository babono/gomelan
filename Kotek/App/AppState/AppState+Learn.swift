//
//  AppState+Learn.swift
//  Kotek
//
//  Moving through Learn (`LearnStage`). The stage lives here, not in the
//  screen, because Watch and the waterfall steps are different screens and
//  the step has to survive the hand-over between them.
//

import Foundation

extension AppState {
    /// From where this pattern was left, or from the top when asked again
    /// (the card's menu, the pause screen).
    func startLearn(_ k: Kotekan, fromStart: Bool = false) {
        selectedKotekan = k
        enterLearn(fromStart ? .watch : LearnProgress.resumeStage(k.id))
    }

    func advanceLearn() {
        guard let stage = learnStage, let id = selectedKotekan?.id else { return }
        guard let next = stage.next else {
            LearnProgress.finished(id)
            leaveLearn(to: .waterfall)
            return
        }
        if next.half == .sangsih, stage.half == .polos { LearnProgress.reachedSangsih(id) }
        enterLearn(next)
    }

    /// Straight to free play — offered once any pattern has been learned.
    func skipLearn() {
        leaveLearn(to: .waterfall)
    }

    /// Quit: back to the picker. Progress up to the half reached is kept.
    func exitLearn() {
        leaveLearn(to: .chooseKotekan)
    }

    private func enterLearn(_ stage: LearnStage) {
        if let half = stage.half {
            chosenHalf = half
            renderHalves()
        }
        learnStage = stage
        screen = .learn
    }

    private func leaveLearn(to route: Route) {
        learnStage = nil
        renderHalves()
        screen = route
    }
}

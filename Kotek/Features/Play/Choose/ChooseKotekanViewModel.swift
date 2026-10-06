//
//  ChooseKotekanViewModel.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import FactoryKit
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class ChooseKotekanViewModel {
    let app: AppState
    let cue: CuePlayer

    let engine = PlayEngine()
    private let displayLink = DisplayLink()

    var position: Double = 0
    var dragOrigin: Double?
    var muted = false

    static let gap: CGFloat = 22
    static var step: CGFloat { KotekanCardView.cardWidth + gap }

    init(app: AppState, cue: CuePlayer = Container.shared.cueService()) {
        self.app = app
        self.cue = cue
    }

    var kotekans: [Kotekan] { app.kotekans }
    var focusedSlot: Int { Int(position.rounded()) }

    var current: Kotekan? {
        kotekans.isEmpty ? nil : kotekans[wrap(focusedSlot)]
    }

    var playable: Bool {
        guard let current else { return false }
        return app.kotekan(current, playableOn: app.profile)
    }

    func isPlayable(_ kotekan: Kotekan) -> Bool {
        app.kotekan(kotekan, playableOn: app.profile)
    }

    func bestRecord(_ kotekan: Kotekan) -> PatternRecord? {
        app.profile.bestRecord(kotekanId: kotekan.id)
    }

    func wrap(_ i: Int) -> Int {
        let n = kotekans.count
        guard n > 0 else { return 0 }
        return ((i % n) + n) % n
    }

    func onAppear() {
        app.showGuideIfFirstRun(.kotekan)
        startPreview()
    }

    func onDisappear() {
        stopPreview()
    }

    func handleScenePhase(_ phase: ScenePhase) {
        if phase == .active { startPreview() } else { stopPreview() }
    }

    func handleMutedChanged(_ isMuted: Bool) {
        engine.partnerAudible = !isMuted
        engine.yourVoiceAudible = !isMuted
        if isMuted { cue.stopKeySamples() }
    }

    func onSlotChanged() {
        startPreview()
    }

    func startPreview() {
        guard let k = current else { return }
        engine.cue = cue
        engine.metronomeEnabled = false
        engine.partnerAudible = !muted
        engine.yourVoiceAudible = !muted
        engine.configure(
            song: k.makeSong(half: .polos, cycles: 1),
            partner: k.makeSong(half: .sangsih, cycles: 1),
            profile: app.profile,
            tempoScale: 1,
            judging: false,
            countIn: false
        )
        engine.start()
        displayLink.onFrame = { [weak self] now in
            self?.engine.tick(now: now)
        }
        displayLink.start()
    }

    func stopPreview() {
        displayLink.stop()
        cue.stop()
    }

    func start(_ k: Kotekan) {
        stopPreview()
        app.chooseKotekan(k)
    }

    func onDragChanged(translationWidth: CGFloat) {
        let origin = dragOrigin ?? position
        dragOrigin = origin
        position = origin - translationWidth / Self.step
    }

    func onDragEnded(
        translationWidth: CGFloat,
        predictedEndTranslationWidth: CGFloat,
        startLocationX: CGFloat,
        width: CGFloat
    ) {
        let origin = dragOrigin ?? position
        dragOrigin = nil

        guard abs(translationWidth) >= 10 else {
            position = origin
            tap(slotUnder(x: startLocationX, width: width, origin: origin))
            return
        }

        let landing = origin - predictedEndTranslationWidth / Self.step
        withAnimation(.snappy(duration: 0.32)) {
            position = (landing.rounded()).clamped(to: origin - 1, origin + 1)
        }
    }

    private func slotUnder(x: CGFloat, width: CGFloat, origin: Double) -> Int {
        Int((Double(x - width / 2) / Double(Self.step) + origin).rounded())
    }

    func tap(_ slot: Int) {
        Task { @concurrent in
            await KajarTick.strike()
        }
        if slot == focusedSlot {
            let k = kotekans[wrap(slot)]
            if isPlayable(k) { start(k) }
        } else {
            withAnimation(.snappy(duration: 0.32)) { position = Double(slot) }
        }
    }
}

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
    /// Whether the preview is what is driving the shared cue player right now.
    private var previewing = false

    static let gap: CGFloat = 22
    static var step: CGFloat {
        KotekanCardView.cardWidth + gap
    }

    init(app: AppState, cue: CuePlayer = Container.shared.cueService()) {
        self.app = app
        self.cue = cue
        // Land on the figure last chosen — or just created — rather than the
        // first card.
        if let id = app.selectedKotekan?.id, let i = app.kotekans.firstIndex(where: { $0.id == id }) {
            position = Double(i)
        }
    }

    var kotekans: [Kotekan] {
        app.kotekans
    }

    var focusedSlot: Int {
        Int(position.rounded())
    }

    /// Every figure, then the "+ Create" card.
    var railCount: Int {
        kotekans.count + 1
    }

    /// The figure at a rail slot, or nil for the create card.
    func kotekan(atSlot slot: Int) -> Kotekan? {
        let i = wrap(slot)
        return i < kotekans.count ? kotekans[i] : nil
    }

    var current: Kotekan? {
        kotekan(atSlot: focusedSlot)
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
        let n = railCount
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
        guard let k = current else { return stopPreview() }
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
        previewing = true
    }

    /// Stops the preview, and the shared cue player only if the preview still
    /// owns it.
    ///
    /// The guard is the whole point. `start` stops the preview and THEN changes
    /// screen, and SwiftUI runs the next screen's `onAppear` before this one's
    /// `onDisappear`. Unguarded, that late second stop landed after the next
    /// screen had started the same CuePlayer, and silenced its entire session:
    /// `started` went false, so every gong, kajar and key sample after it was
    /// dropped by `ensureLive()`. The waterfall, which starts its clock in
    /// `onAppear`, had no sound at all. PlayView only escaped because it waits
    /// 400 ms before starting.
    func stopPreview() {
        displayLink.stop()
        guard previewing else { return }
        previewing = false
        cue.stop()
    }

    func start(_ k: Kotekan) {
        stopPreview()
        app.playKotekan(k)
    }

    func create() {
        stopPreview()
        app.openCreateKotek()
    }

    func coop(_ k: Kotekan) {
        stopPreview()
        app.openCoop(k)
    }

    func edit(_ k: Kotekan) {
        stopPreview()
        app.openEditKotek(k)
    }

    /// The figure waiting on the delete confirmation.
    var pendingDelete: Kotekan?
    var deleting = false
    var deleteError: String?

    func delete(_ k: Kotekan) {
        guard !deleting else { return }
        deleting = true
        deleteError = nil
        Task {
            defer { deleting = false }
            do {
                try await app.deleteKotekan(k)
                // R The rail just lost a card; stay on the slot, which is now
                // R the next figure (or the create card), rather than jumping.
                position = Double(min(focusedSlot, railCount - 1))
                startPreview()
            } catch {
                deleteError = "Couldn't delete \(k.name). Check your connection and try again."
            }
        }
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
            guard let k = kotekan(atSlot: slot) else { return create() }
            if isPlayable(k) { start(k) }
        } else {
            withAnimation(.snappy(duration: 0.32)) { position = Double(slot) }
        }
    }
}

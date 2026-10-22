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
    /// Narrows the rail by name. Typing jumps back to the first match.
    var query = "" {
        didSet { if query != oldValue { position = 0 } }
    }

    /// Whether the preview is what is driving the shared cue player right now.
    private var previewing = false

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
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return app.kotekans }
        return app.kotekans.filter { $0.name.localizedStandardContains(q) }
    }

    /// The rail wraps round, except over search results: two matches looped
    /// would fill the screen with copies of themselves.
    var loops: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var focusedSlot: Int {
        Int(position.rounded())
    }

    /// Every figure. The "+ Create" card that used to close the rail is the
    /// Create button above it now: at the end of the rail it was a swipe
    /// past every figure away, and easy to never find.
    var railCount: Int {
        kotekans.count
    }

    /// The figure at a rail slot; nil past either end of a rail that doesn't
    /// loop, or when nothing matches.
    func kotekan(atSlot slot: Int) -> Kotekan? {
        guard loops || kotekans.indices.contains(slot) else { return nil }
        let i = wrap(slot)
        return kotekans.indices.contains(i) ? kotekans[i] : nil
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
        applyMuted()
        if isMuted {
            cue.stopKeySamples()
            cue.stopColotomic()
        }
    }

    /// Mute is the whole preview, gong and kajar included. The engine keeps the
    /// colotomic frame on in a session because judging is measured against it;
    /// the preview never judges, so here it is just more sound under a "Muted" label.
    private func applyMuted() {
        engine.partnerAudible = !muted
        engine.yourVoiceAudible = !muted
        engine.colotomicAudible = !muted
    }

    func onSlotChanged() {
        startPreview()
    }

    func startPreview() {
        guard let k = current else { return stopPreview() }
        engine.cue = cue
        applyMuted()
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
                // R the next figure (or the last one), rather than jumping.
                position = Double(max(0, min(focusedSlot, railCount - 1)))
                startPreview()
            } catch {
                deleteError = "Couldn't delete \(k.name). Check your connection and try again."
            }
        }
    }

    /// `step` is the distance between card centres, which the view works out
    /// from its width (`CarouselFit`) — it is not a constant.
    func onDragChanged(translationWidth: CGFloat, step: CGFloat) {
        let origin = dragOrigin ?? position
        dragOrigin = origin
        position = clampToRail(origin - translationWidth / step)
    }

    private func clampToRail(_ p: Double) -> Double {
        loops ? p : p.clamped(to: 0, Double(max(0, railCount - 1)))
    }

    func onDragEnded(
        translationWidth: CGFloat,
        predictedEndTranslationWidth: CGFloat,
        startLocationX: CGFloat,
        width: CGFloat,
        step: CGFloat
    ) {
        let origin = dragOrigin ?? position
        dragOrigin = nil

        guard abs(translationWidth) >= 10 else {
            position = origin
            tap(slotUnder(x: startLocationX, width: width, step: step, origin: origin))
            return
        }

        let landing = origin - predictedEndTranslationWidth / step
        withAnimation(.snappy(duration: 0.32)) {
            position = clampToRail((landing.rounded()).clamped(to: origin - 1, origin + 1))
        }
    }

    private func slotUnder(x: CGFloat, width: CGFloat, step: CGFloat, origin: Double) -> Int {
        Int((Double(x - width / 2) / Double(step) + origin).rounded())
    }

    /// The carousel's taps arrive through its drag, not a button, so the tick is
    /// struck here. The centred card goes on to the session (Start is gone);
    /// a side card is brought to the middle, which is how a figure is heard.
    func tap(_ slot: Int) {
        KajarTick.strike()
        guard let k = kotekan(atSlot: slot) else { return }
        if slot == focusedSlot {
            if isPlayable(k) { start(k) }
        } else {
            withAnimation(.snappy(duration: 0.32)) { position = Double(slot) }
        }
    }
}

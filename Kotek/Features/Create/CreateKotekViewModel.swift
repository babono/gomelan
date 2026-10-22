//
//  CreateKotekViewModel.swift
//  Kotek
//
//  The Create Kotek flow: write it on the piano roll, review, save. One route,
//  two steps — they share one draft, and two routes would have meant parking
//  that draft on AppState for a feature nothing else reads.
//
//  The sensors record INTO the piano roll rather than on a screen of their
//  own. There used to be a Manual/Automatic choice up front and a separate
//  recording screen that played the half twice against a kempli and kept what
//  both takes agreed on. It meant picking a method before knowing which suited
//  the figure, and a recording could only be fixed on the review screen.
//  Recording is now step entry, as in a DAW: the line waits on a hit, writes
//  it for the half being written, and steps on by the snap value. No tempo to
//  keep, so no second take to cross-check against.
//

import FactoryKit
import Foundation
import Observation
import OSLog
import SwiftUI

enum PianoRollTool: Equatable {
    case notes
    case colotomic(ColotomicInstrument)
    case erase
}

@Observable
@MainActor
final class CreateKotekViewModel {
    enum Step {
        case compose, review
    }

    let app: AppState
    let cue: CuePlayer
    let draft = KotekanDraft()
    /// The saved figure this draft was opened from, or nil for a new one.
    let editing: Kotekan?

    var step: Step = .compose
    /// The half the grid writes into, and the half the sensors record.
    var writing: KotekanHalf = .polos
    var snap = Subdivision.eighth

    var saving = false
    var saveError: String?

    /// What a tap on the piano roll does: write a stroke for `writing`, write
    /// a gong/kajar/klentong, or delete. Picking a half goes back to strokes.
    var tool: PianoRollTool = .notes

    // MARK: Preview

    private let displayLink = DisplayLink()
    private(set) var playing = false
    /// Where the playhead is, in ticks from the top of the figure. Pause leaves
    /// it where it is; stop puts it back to 0. Read only by the playhead and
    /// the clock, so the per-frame write redraws those and not the grid.
    private(set) var playhead: Double = 0 {
        didSet {
            let bar = Int(playhead) / KotekanDraft.ticksPerBar
            if bar != playheadBar { playheadBar = bar }
        }
    }

    /// The bar the playhead is in. The grid scrolls to follow this rather than
    /// `playhead`, so it hears about the line once a bar, not once a frame.
    private(set) var playheadBar = 0
    @ObservationIgnored private var lastFrame: Double?

    // MARK: Recording

    /// The app's one controller connection (`Container.sensorService`). A
    /// gangsa with a controller set up is already being followed by RootView;
    /// without one, recording takes any controller in reach itself.
    let sensor: GangsaSensor
    private(set) var recording = false
    /// Without a controller set up: which bilah input 0 is taped to. The
    /// prototype's sensors sit on neighbouring bilah, in input order.
    var firstSensorKey = 4

    init(
        app: AppState,
        cue: CuePlayer = Container.shared.cueService(),
        sensor: GangsaSensor = Container.shared.sensorService()
    ) {
        self.app = app
        self.cue = cue
        self.sensor = sensor
        editing = app.editingKotekan
        if let editing { draft.load(editing) }
        firstSensorKey = min(firstSensorKey, max(0, keyCount - sensorCount))
    }

    /// Inputs on the connected controller; the prototype's three until it says.
    var sensorCount: Int {
        sensor.info?.inputCount ?? GangsaSensor.legacyInputCount
    }

    /// The gangsa has its own controller map (§3.6.5), so there is nothing to
    /// place: every input already knows its bilah.
    var usesControllerMap: Bool {
        app.profile.controller != nil
    }

    var sensorKeys: ClosedRange<Int> {
        firstSensorKey ... firstSensorKey + sensorCount - 1
    }

    /// Every placement of the prototype sensors that fits the instrument.
    var sensorPlacements: [Int] {
        Array(0 ... max(0, keyCount - sensorCount))
    }

    /// Controller input → key, the same rule the waterfall plays by: the
    /// gangsa's own map, or the prototype's neighbouring bilah. Nil is
    /// an input with no key on it, and its hits are dropped.
    func key(forInput input: Int) -> Int? {
        if usesControllerMap { return app.profile.keyForInput[input] }
        let key = firstSensorKey + input
        return key < keyCount ? key : nil
    }

    var keyCount: Int {
        max(1, app.profile.keyCount)
    }

    // MARK: - Navigation

    func back() {
        leave()
        switch step {
        case .compose: app.backToKotekan()
        case .review: step = .compose
        }
    }

    func review() {
        leave()
        step = .review
    }

    /// Stop everything that makes a sound or holds the radio.
    func leave() {
        stopRecording()
        stopPreview()
    }

    // MARK: - Recording

    func toggleRecording() {
        if recording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !recording else { return }
        pause()
        cue.start()
        sensor.onHit = { [weak self] hit in
            guard let self, let key = key(forInput: hit.input) else { return }
            record(key: key)
        }
        if !usesControllerMap { sensor.use(.any) }
        recording = true
    }

    func stopRecording() {
        guard recording else { return }
        // Not `use(.none)`: RootView hands the controller back to the active
        // gangsa as this screen goes, and may already have.
        sensor.onHit = nil
        recording = false
    }

    /// A hit: write it at the line for the half being written, then step on.
    func record(key: Int) {
        let draft = draft
        let tick = Int(playhead) / snap.ticks * snap.ticks
        guard tick < KotekanDraft.timelineTicks else { return }
        draft.edit { draft.set(half: writing, tick: tick, key: key, length: snap.ticks) }
        draft.source = .automatic
        audition(key)
        playhead = Double(min(tick + snap.ticks, KotekanDraft.timelineTicks - 1))
    }

    /// Step on without writing — a rest.
    func recordRest() {
        let tick = Int(playhead) / snap.ticks * snap.ticks
        playhead = Double(min(tick + snap.ticks, KotekanDraft.timelineTicks - 1))
    }

    /// Put the line at `tick`, snapped — a tap on the ruler.
    func seek(toTick tick: Int) {
        pause()
        let snapped = Int((Double(tick) / Double(snap.ticks)).rounded()) * snap.ticks
        playhead = Double(snapped.clamped(to: 0, KotekanDraft.timelineTicks - 1))
    }

    // MARK: - Preview

    // The preview used to be the picker's `PlayEngine`. It plays a finished
    // figure from the top with its own gong cycle, and could neither pause in
    // place nor play the gong, kajar and klentong written here. This walks the
    // draft itself: it reads the notes every frame, so an edit or a tempo
    // change is heard on the next pass without a restart.

    func togglePlay() {
        if playing {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard !draft.isEmpty, !playing else { return }
        stopRecording()
        if playhead >= Double(draft.lengthTicks) { playhead = 0 }
        cue.start()
        lastFrame = nil
        displayLink.onFrame = { [weak self] now in self?.frame(now: now) }
        displayLink.start()
        playing = true
    }

    func pause() {
        displayLink.stop()
        playing = false
    }

    /// Stop and rewind. Also what leaving the screen does.
    func stopPreview() {
        pause()
        cue.stop()
        playhead = 0
    }

    private func frame(now: Double) {
        guard !draft.isEmpty else { return stopPreview() }
        let length = Double(draft.lengthTicks)
        let elapsed = lastFrame.map { now - $0 } ?? 0
        lastFrame = now

        // The figure can shrink under the playhead when its last note is
        // taken out; pick it up from the top.
        var from = playhead < length ? playhead : 0
        var to = from + elapsed * Double(draft.bpm) / 60 * Double(KotekanDraft.ticksPerBeat)
        if to >= length {
            sound(from: from, to: length)
            from = 0
            to = (to - length).truncatingRemainder(dividingBy: length)
        }
        sound(from: from, to: to)
        playhead = to
    }

    /// Everything that starts in `from ..< to`. Half-open, so a stroke on the
    /// boundary between two frames sounds once.
    private func sound(from: Double, to: Double) {
        guard to > from else { return }
        let range = from ..< to
        for note in draft.notes where range.contains(Double(note.tick)) {
            cue.playKeySample(index: note.key, pan: note.half == .polos ? -0.3 : 0.3, volume: 0.8)
        }
        for hit in draft.colotomic where range.contains(Double(hit.tick)) {
            strike(hit.instrument)
        }
    }

    /// Sound one bilah — the piano roll's answer to a tap.
    func audition(_ key: Int) {
        cue.start()
        cue.playKeySample(index: key, volume: 0.7)
    }

    func audition(_ instrument: ColotomicInstrument) {
        cue.start()
        strike(instrument)
    }

    private func strike(_ instrument: ColotomicInstrument) {
        switch instrument {
        case .gong: cue.playGong()
        case .kempur: cue.playKempur()
        case .klentong: cue.playKlentong()
        case .kajar: cue.playKajar()
        }
    }

    // MARK: - Save

    var canSave: Bool {
        !draft.isEmpty && !saving
    }

    func save() {
        guard canSave else { return }
        leave()
        saving = true
        saveError = nil
        // Same id when editing: the save then replaces the figure, not adds one.
        let k = draft.kotekan(id: editing?.id ?? UUID().uuidString.lowercased())
        Task {
            defer { saving = false }
            do {
                try await app.saveKotekan(k)
            } catch {
                app.log.error("kotekan save failed: \(String(describing: error), privacy: .public)")
                saveError = "Couldn't save — check your connection and try again."
            }
        }
    }
}

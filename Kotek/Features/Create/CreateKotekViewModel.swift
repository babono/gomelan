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
//  Recording runs like playback: the line moves at the tempo over the gong
//  cycle, and a hit is written for the half being written in the snap step
//  the line is in. It was step entry for a while — the line waited on a hit and
//  stepped on by the snap, with a Rest button for the gaps — but a kotekan is
//  felt against the kajar, and nobody could play one a stroke at a time.
//
//  A hit comes from the sensors or from the gangsa drawn under the roll —
//  tapped like GarageBand's keyboard. Both go through `record(key:)`.
//

import FactoryKit
import Foundation
import Observation
import OSLog
import SwiftUI

enum PianoRollTool: Equatable {
    case notes
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
    var snap = Subdivision.quarter
    /// The play screen's speed multiplier, for playing back and recording.
    /// Not saved: the figure keeps its tempo, so a take recorded slow plays
    /// back at full speed.
    var tempoScale = 1.0
    /// The touch gangsa is out, and the roll above it is a small overview;
    /// tapping the overview puts it away and opens the roll to edit.
    var showsGangsa = true
    /// The roll's zoom, both ways: 1 is a quarter cell and a row each big
    /// enough to tap (`PianoRollGrid`).
    var zoom: CGFloat = 1

    var saving = false
    var saveError: String?

    /// What a tap on the piano roll does: write a stroke for `writing`, or
    /// delete. Picking a half goes back to strokes.
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
    /// Ticks written this take, so the moving line does not sound them twice.
    @ObservationIgnored private var take: Set<Int> = []
    /// The count before a recording: the number on screen, nil once the line
    /// moves. Ticks of it left in `lead` — counted at the tempo, so the
    /// fifth kajar is the downbeat the take starts on.
    private(set) var countIn: Int?
    @ObservationIgnored private var lead: Double = 0
    private static let countInBeats = 4

    // MARK: Recording

    /// The app's one controller connection (`Container.sensorService`),
    /// already following the gangsa's own controller (RootView).
    let sensor: GangsaSensor
    private(set) var recording = false

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
        #if DEBUG
            if UserDefaults.standard.string(forKey: "screenshot") == "create-polos-roll" { showsGangsa = false }
        #endif
    }

    /// Controller input → key, from the gangsa's controller setup (§3.6.5),
    /// the same map the waterfall plays by. Nil is an input with no key on
    /// it, and its hits are dropped.
    ///
    /// There was a fallback for a gangsa with no setup: take any controller
    /// in reach and pick which neighbouring bilah its sensors were taped to.
    /// A second, lesser setup on the record bar, and it read as noise; a
    /// gangsa without a controller records from the drawn one instead.
    func key(forInput input: Int) -> Int? {
        app.profile.keyForInput[input]
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

    /// From wherever the line is, after a count of four on the kajar at the
    /// tempo. It does not loop: like a DAW recording, it runs on over the
    /// empty roll until stopped or the roll ends.
    func startRecording() {
        guard !recording else { return }
        pause()
        cue.start()
        sensor.onHit = { [weak self] hit in
            guard let self, let key = key(forInput: hit.input) else { return }
            record(key: key)
        }
        take = []
        draft.beginGroup()
        recording = true
        lead = Double(Self.countInBeats * KotekanDraft.ticksPerBeat)
        countIn = 1
        cue.playKajar()
        run()
    }

    func stopRecording() {
        guard recording else { return }
        // Not `use(.none)`: RootView hands the controller back to the active
        // gangsa as this screen goes, and may already have.
        sensor.onHit = nil
        recording = false
        // The whole take, one undo.
        draft.endGroup()
        lead = 0
        countIn = nil
        pause()
    }

    /// A hit: written in the snap step the line is in, for the half being
    /// written. Not the nearest line: past the middle of a step that was the
    /// next one, so a stroke played on a beat could land on the beat after.
    func record(key: Int) {
        let draft = draft
        // In the count, only the last half step still lands, on the line's
        // start; anything earlier is only heard.
        let at = lead > 0 && lead <= Double(snap.ticks) / 2 ? playhead : playhead - lead
        let tick = Int((at / Double(snap.ticks)).rounded(.down)) * snap.ticks
        guard tick >= 0, tick < KotekanDraft.timelineTicks else { return audition(key) }
        draft.edit { draft.set(half: writing, tick: tick, key: key, length: snap.ticks) }
        draft.source = .automatic
        take.insert(tick)
        audition(key)
    }

    /// A bilah tapped on the drawn gangsa: written while recording, as a
    /// sensor hit is, otherwise only heard.
    func touch(key: Int) {
        if recording { record(key: key) } else { audition(key) }
    }

    /// Put the line at `tick`, snapped — a drag on the ruler. A recording
    /// keeps running from there.
    func seek(toTick tick: Int) {
        if !recording { pause() }
        let snapped = Int((Double(tick) / Double(snap.ticks)).rounded()) * snap.ticks
        playhead = Double(snapped.clamped(to: 0, KotekanDraft.timelineTicks - 1))
    }

    // MARK: - Preview

    // The preview used to be the picker's `PlayEngine`. It plays a finished
    // figure from the top with its own gong cycle, and could neither pause in
    // place nor play the gong, kajar and klentong written here. This walks the
    // draft itself: it reads the notes every frame, so an edit or a tempo
    // change is heard on the next pass without a restart.

    /// Also how a recording is stopped from the transport.
    func togglePlay() {
        if playing || recording {
            stopRecording()
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
        playing = true
        run()
    }

    /// Start the clock under the line, for playing or recording.
    private func run() {
        lastFrame = nil
        displayLink.onFrame = { [weak self] now in self?.frame(now: now) }
        displayLink.start()
    }

    func pause() {
        displayLink.stop()
        playing = false
    }

    /// Stop and rewind. Also what leaving the screen does.
    func stopPreview() {
        stopRecording()
        pause()
        cue.stop()
        playhead = 0
    }

    private func frame(now: Double) {
        let elapsed = lastFrame.map { now - $0 } ?? 0
        lastFrame = now
        let step = elapsed * Double(draft.bpm) * tempoScale / 60 * Double(KotekanDraft.ticksPerBeat)

        if recording {
            var step = step
            if lead > 0 {
                lead -= step
                guard lead <= 0 else {
                    // 1 with more than three beats to go, 4 in the last one.
                    let n = Self.countInBeats + 1 - Int((lead / Double(KotekanDraft.ticksPerBeat)).rounded(.up))
                    if n != countIn {
                        countIn = n
                        cue.playKajar()
                    }
                    return
                }
                // The count ran out mid-frame: the line takes the rest of it.
                countIn = nil
                step = -lead
                lead = 0
            }
            let end = Double(KotekanDraft.timelineTicks)
            let to = min(playhead + step, end)
            sound(from: playhead, to: to)
            playhead = to
            if to >= end { stopRecording() }
            return
        }

        guard !draft.isEmpty else { return stopPreview() }
        let length = Double(draft.lengthTicks)
        // The figure can shrink under the playhead when its last note is
        // taken out; pick it up from the top.
        var from = playhead < length ? playhead : 0
        var to = from + step
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
            // A hit written on the line the take starts on was heard as it
            // was played; the line leaving it must not strike it again.
            if recording, note.half == writing, take.contains(note.tick) { continue }
            cue.playKeySample(index: note.key, pan: note.half == .polos ? -0.3 : 0.3, volume: 0.8)
        }
        // By beat, not from `draft.colotomic`: a recording runs past the end
        // of the figure, where the draft lays no cycle yet.
        let beat = KotekanDraft.ticksPerBeat
        for tick in stride(from: Int((from / Double(beat)).rounded(.up)) * beat, to: Int(to.rounded(.up)), by: beat)
            where range.contains(Double(tick))
        {
            KotekanDraft.colotomic(atBeat: tick / beat).forEach(strike)
        }
    }

    /// Sound one bilah — the piano roll's answer to a tap.
    func audition(_ key: Int) {
        cue.start()
        cue.playKeySample(index: key, volume: 0.7)
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

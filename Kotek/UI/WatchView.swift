//
//  WatchView.swift
//  Kotek
//
//  The demo half of the session (PRD §4 Flow C): the app plays the chosen
//  kotekan half and lights the bilah on the live feed while the player just
//  watches and listens. Nothing is detected, nothing is scored here.
//
//  It used to be the first loop of the play screen, which meant sitting through
//  the whole figure once with the mallets in your hands and no way to hear it
//  twice. On its own screen the demo can loop for as long as you like, run
//  slower than tempo, and hand over only when you say so.
//

import SwiftUI

struct WatchView: View {
    @Environment(AppState.self) private var app
    let camera: CameraController
    let cue: CuePlayer

    @State private var engine = PlayEngine()
    @State private var displayLink = DisplayLink()
    @State private var speed: Double = 1.0
    /// One cycle of each half — the demo loops the figure rather than playing
    /// all the repetitions picked for the run, and sounds both halves so you
    /// hear the interlock, not just your own part.
    @State private var song: Song?
    @State private var partnerSong: Song?

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session, controller: camera)
                .ignoresSafeArea()

            OverlayView(keys: app.profile.keys, engine: engine)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .background(Theme.ink.opacity(0.75))

                Spacer()

                bottomPanel
            }
        }
        .background(Theme.ink)
        .onAppear(perform: setup)
        .onDisappear { displayLink.stop() }
    }

    // MARK: - Chrome

    private var sessionTitle: String {
        guard let k = app.selectedKotekan else { return "" }
        return "\(k.name) · \(app.chosenHalf.title)"
    }

    private var topBar: some View {
        HStack {
            Button {
                teardown()
                app.backToCycles()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.sans(14, weight: .medium))
                    Text("Back").font(.sans(16))
                }
                .foregroundStyle(Theme.cream)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(sessionTitle)
                .font(.sans(13, weight: .semibold))
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(Theme.copper)

            Spacer()

            Text(passLabel)
                .font(.sans(14))
                .foregroundStyle(Theme.inkStone)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    /// The count-in reads as such; after that, how many times round it has gone.
    private var passLabel: String {
        engine.phase == .countIn ? "Count-in" : "Pass \(engine.loopIndex + 1)"
    }

    private var bottomPanel: some View {
        @Bindable var app = app

        //R The "Watch and listen" banner said what the screen title already
        //R says. The room it was taking is the mixer's now.
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                VoiceMixer(yourHalf: app.chosenHalf,
                           yourVoiceAudible: $app.yourVoiceAudible,
                           partnerAudible: $app.partnerAudible,
                           colotomicAudible: $app.colotomicAudible)
                    .layoutPriority(-1)

                Spacer(minLength: 8)

                riverToggle

                SpeedPicker(scale: $speed)

                PillButton(title: "I'm ready", style: .filled,
                           tint: Theme.terracotta, compact: true) {
                    handOver()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.ink.opacity(0.8))

            if app.riverVisible {
                NotesRiver(engine: engine,
                           keyRange: keyRange,
                           keyCount: app.profile.keys.count,
                           yourHalf: app.chosenHalf)
            }
        }
        .onChange(of: speed) { _, new in
            app.demoTempoScale = new
            restart()
        }
        .onChange(of: app.yourVoiceAudible) { _, new in engine.yourVoiceAudible = new }
        .onChange(of: app.partnerAudible) { _, new in engine.partnerAudible = new }
        .onChange(of: app.colotomicAudible) { _, new in
            engine.colotomicAudible = new
            if !new { cue.stopColotomic() }
        }
    }

    /// Hide the score to give the instrument the whole screen.
    private var riverToggle: some View {
        Button {
            app.riverVisible.toggle()
        } label: {
            Image(systemName: app.riverVisible ? "rectangle.bottomthird.inset.filled" : "rectangle")
                .font(.sans(15, weight: .medium))
                .foregroundStyle(app.riverVisible ? Theme.ink : Theme.copper)
                .frame(width: 38, height: 34)
                .background(app.riverVisible ? Theme.copper : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.copper.opacity(0.6), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    /// The lanes the river draws — both halves of the figure.
    private var keyRange: ClosedRange<Int> {
        app.selectedKotekan?.voicedKeyRange ?? 0...max(0, app.profile.keys.count - 1)
    }

    // MARK: - Lifecycle

    private func setup() {
        camera.start()
        if app.fixedMount { camera.lockFocusAndExposure() } else { camera.enableContinuousAutoFocus() }

        song = app.demoSong
        partnerSong = app.demoPartnerSong
        speed = app.demoTempoScale
        engine.cue = cue
        engine.metronomeEnabled = app.metronomeEnabled
        engine.referenceToneEnabled = app.referenceToneEnabled
        engine.partnerAudible = app.partnerAudible
        engine.yourVoiceAudible = app.yourVoiceAudible
        engine.colotomicAudible = app.colotomicAudible

        start()
    }

    private func start() {
        guard let song else {
            app.backToCycles()
            return
        }
        engine.configure(song: song, partner: partnerSong, mode: .play, profile: app.profile,
                         tempoScale: speed, role: .demo)
        engine.start()
        displayLink.onFrame = { now in engine.tick(now: now) }
        displayLink.start()
    }

    /// A speed change re-runs the demo from the count-in — the clock, the loop
    /// length and the cue schedule all derive from the tempo.
    private func restart() {
        displayLink.stop()
        cue.stopKeySamples()
        start()
    }

    /// Hand the instrument over. The cue player is deliberately left running:
    /// booting it decodes every sample, which is slow enough to skew the clock
    /// at the top of the run (see PlayEngine.start), and PlayView needs it a
    /// second later anyway. Only the ringing gangsa samples are cut.
    private func handOver() {
        displayLink.stop()
        cue.stopKeySamples()
        app.beginPractice()
    }

    /// Leaving the session altogether — silence everything.
    private func teardown() {
        displayLink.stop()
        cue.stop()
    }
}

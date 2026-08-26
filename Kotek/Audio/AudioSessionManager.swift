//
//  AudioSessionManager.swift
//  Kotek
//
//  Configures the shared audio session for simultaneous capture + cue playback
//  (PRD §13.2). `.measurement` mode disables the system's automatic gain control
//  and echo cancellation, both of which would corrupt onset detection and pitch
//  analysis. Do not omit it.
//

import AVFoundation

enum AudioSessionManager {

    /// The session for the splash and title screens, where nothing is captured.
    ///
    /// `.playback` rather than the capture configuration below, because
    /// `.measurement` mode is brutal to output level — defeating the system's
    /// signal processing is the entire point of it, and that includes whatever
    /// makes quiet material carry on a phone speaker. The title music survived
    /// it (broadband, stereo, and already taken to full volume for exactly this
    /// reason); a single mono kempur, whose energy is nearly all low frequency,
    /// did not. It was being played at full scale and still inaudible.
    ///
    /// Nothing before the capture flow needs a microphone, so nothing before it
    /// needs to pay that. `configure()` MUST be restored before any capture —
    /// see the call sites, which are deliberately belt-and-braces.
    static func configureForPlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("[AudioSession] playback configuration failed: \(error)")
        }
    }

    /// Configure before any capture. Idempotent, and safe to call repeatedly.
    ///
    /// No longer only at launch: the app opens on `configureForPlayback()`, so
    /// this is what puts the recording configuration back. Detection depends on
    /// `.measurement`, so anything that listens calls this first rather than
    /// assuming it is already in force.
    static func configure() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .measurement,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setPreferredSampleRate(44100)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            // Surfaced to the console; the app still runs but detection degrades.
            print("[AudioSession] configuration failed: \(error)")
        }
    }

    static func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static var recordAuthorized: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }
}

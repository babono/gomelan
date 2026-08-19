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

    /// Configure once at launch, before any capture.
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

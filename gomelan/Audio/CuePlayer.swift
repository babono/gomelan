//
//  CuePlayer.swift
//  gomelan
//
//  The audio cue layer (PRD §5.4). Because the screen is small and the player
//  stands over the instrument, audio carries as much guidance as vision:
//
//   - metronome click on the beat (toggleable)
//   - reference tone: the upcoming key, played quietly one beat ahead — the
//     closest digital equivalent to learning by ear
//   - short distinct hit/miss feedback sounds
//
//  Cue output routes through the speaker and must not overpower the real
//  instrument's onset detection. Ducking around strike windows is a known TODO
//  (§5.4) and left as a hook here.
//

import AVFoundation

final class CuePlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate: Double = 44100
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    private var started = false

    func start() {
        guard !started else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
            player.play()
            started = true
        } catch {
            print("[CuePlayer] failed to start: \(error)")
        }
    }

    func stop() {
        guard started else { return }
        player.stop()
        engine.stop()
        started = false
    }

    // MARK: - Cues

    /// A subtle metronome click on the beat.
    func playClick() {
        schedule(tone(frequency: 1600, durationMs: 25, gain: 0.15))
    }

    /// The calibrated pitch of the upcoming key, played quietly one beat ahead.
    func playReference(hz: Double) {
        schedule(tone(frequency: hz, durationMs: 180, gain: 0.18))
    }

    func playHit() {
        schedule(tone(frequency: 880, durationMs: 90, gain: 0.2))
    }

    func playMiss() {
        schedule(tone(frequency: 180, durationMs: 120, gain: 0.2))
    }

    // MARK: - Tone synthesis

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        guard started else { return }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    /// A short sine tone with a quick attack/decay envelope to avoid clicks.
    private func tone(frequency: Double, durationMs: Double, gain: Float) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * durationMs / 1000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]

        let n = Int(frameCount)
        let attack = Int(Double(n) * 0.1)
        let release = Int(Double(n) * 0.3)
        for i in 0..<n {
            let phase = 2 * Double.pi * frequency * Double(i) / sampleRate
            var env: Double = 1
            if i < attack { env = Double(i) / Double(max(attack, 1)) }
            else if i > n - release { env = Double(n - i) / Double(max(release, 1)) }
            samples[i] = Float(sin(phase) * env) * gain
        }
        return buffer
    }
}

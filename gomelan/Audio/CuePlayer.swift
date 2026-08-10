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
    
    // Recorded-sample playback (demo pattern, colotomic layer)
    private let sampleNode = AVAudioPlayerNode()
    private let gongNode = AVAudioPlayerNode()
    private let kempurNode = AVAudioPlayerNode()
    private let kemongNode = AVAudioPlayerNode()
    private var keyBuffers: [Int: AVAudioPCMBuffer] = [:]
    private var gongBuffer: AVAudioPCMBuffer?
    private var kempurBuffer: AVAudioPCMBuffer?
    private var kemongBuffer: AVAudioPCMBuffer?

    func start() {
        guard !started else { return }
        
        configureAudioSession()
        
        for i in 0..<10 { keyBuffers[i] = loadBuffer("key\(i)") }
        gongBuffer = loadBuffer("gong")
        kempurBuffer = loadBuffer("kempur")
        kemongBuffer = loadBuffer("kemong")
        
        engine.attach(player)
        engine.attach(sampleNode)
        engine.attach(gongNode)
        engine.attach(kempurNode)
        engine.attach(kemongNode)
        
        engine.connect(player, to: engine.mainMixerNode, format: format)
        if let f = keyBuffers[0]?.format {
            engine.connect(sampleNode, to: engine.mainMixerNode, format: f)
        }
        if let f = gongBuffer?.format {
            engine.connect(gongNode, to: engine.mainMixerNode, format: f)
        }
        if let f = kempurBuffer?.format {
            engine.connect(kempurNode, to: engine.mainMixerNode, format: f)
        }
        if let f = kemongBuffer?.format {
            engine.connect(kemongNode, to: engine.mainMixerNode, format: f)
        }
        
        //givig the mixer enough headroom
        engine.mainMixerNode.outputVolume = 1.0
        
        engine.prepare()
        do {
            try engine.start()
            player.play()
            sampleNode.play()
            gongNode.play()
            kempurNode.play()
            kemongNode.play()
            started = true
        } catch {
            print("[CuePlayer] failed to start: \(error)")
        }
    }

    func stop() {
        guard started else { return }
        player.stop()
        sampleNode.stop()
        gongNode.stop()
        kempurNode.stop()
        kemongNode.stop()
        engine.stop()
        started = false
    }
    
    // MARK: - Audio Session

        private func configureAudioSession() {
            let session = AVAudioSession.sharedInstance()

            do {
                try session.setCategory(
                    .playAndRecord,
                    mode: .measurement,
                    options: [
                        .defaultToSpeaker,
                        .mixWithOthers
                    ]
                )

                try session.setActive(true)

            } catch {
                print("[CuePlayer] Audio session error: \(error)")
            }
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
    
    // MARK: - Recorded-sample cues

    func playKeySample(index: Int) {
        guard started, let buf = keyBuffers[index] else { return }
        sampleNode.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
    }

    func playGong() {
        guard started, let buf = gongBuffer else { return }
        gongNode.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
    }

    func playKempur() {
        guard started, let buf = kempurBuffer else { return }
        kempurNode.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
    }

    func playKemong() {
        guard started, let buf = kemongBuffer else { return }
        kemongNode.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
    }
    
    // MARK: - Recorded sample scheduling

        private func scheduleRecordedSample(
            node: AVAudioPlayerNode,
            buffer: AVAudioPCMBuffer,
            atHostSeconds: Double?
        ) {

            if let seconds = atHostSeconds {

                let hostTime = AVAudioTime.hostTime(
                    forSeconds: seconds
                )

                let audioTime = AVAudioTime(
                    hostTime: hostTime
                )

                node.scheduleBuffer(
                    buffer,
                    at: audioTime,
                    options: [],
                    completionHandler: nil
                )

            } else {

                node.scheduleBuffer(
                    buffer,
                    at: nil,
                    options: [],
                    completionHandler: nil
                )
            }
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
    
    // MARK: - Sample loading

    private func loadBuffer(_ name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url),
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                          frameCapacity: AVAudioFrameCount(file.length))
        else {
            print("[CuePlayer] missing sample: \(name).wav — check it's in Resources and the target")
            return nil
        }
        try? file.read(into: buf)
        return buf
    }
}

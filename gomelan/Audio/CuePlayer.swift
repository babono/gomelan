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
    private var keyBuffers: [Int: AVAudioPCMBuffer] = [:]
    private var gongBuffer: AVAudioPCMBuffer?
    private var kempurBuffer: AVAudioPCMBuffer?
    private var kemongBuffer: AVAudioPCMBuffer?

    //R --------------------------------------------------------------------
    //R Voice pool.
    //R
    //R Previously each sound owned ONE AVAudioPlayerNode and every cue called
    //R scheduleBuffer(at: nil) on it. On an already-playing node that APPENDS to
    //R the node's queue — the buffer starts only after everything before it has
    //R finished. The samples are long (key* 2s, kemong 3s, gong 8s) and the cues
    //R come fast (a key every ~230ms, a kemong every ~1.9s, a gong every 7.5s),
    //R so each sound fell further and further behind its own visual cue and kept
    //R sounding long after the example was over. Hence: gong not matching the
    //R circle, gangsa not matching the bilah, gangsa still ringing in "Your turn".
    //R
    //R Now every cue takes the next free node out of a pool and starts it
    //R immediately, so a cue always sounds on the frame it was asked for.
    //R --------------------------------------------------------------------
    private enum Voice: Hashable { case key(Int), gong, kempur, kemong }  //R
    private let voiceCount = 12                                          //R
    private var voices: [AVAudioPlayerNode] = []                         //R
    private var nextVoice = 0                                            //R
    /// Node currently carrying each source, so a re-strike cuts its own ring.
    private var activeVoice: [Voice: AVAudioPlayerNode] = [:]            //R
    /// Nodes carrying gangsa samples, so the example can be silenced wholesale.
    private var keyVoices: Set<ObjectIdentifier> = []                    //R

    func start() {
        guard !started else { return }

        configureAudioSession()

        for i in 0..<10 { keyBuffers[i] = loadBuffer("key\(i)") }
        gongBuffer = loadBuffer("gong")
        kempurBuffer = loadBuffer("kempur")
        kemongBuffer = loadBuffer("kemong")

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        //R All bundled samples share one processing format, so one pool serves
        //R every recorded cue.
        let sampleFormat = keyBuffers[0]?.format ?? gongBuffer?.format ?? format
        voices = (0..<voiceCount).map { _ in AVAudioPlayerNode() }
        for node in voices {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: sampleFormat)
        }

        //givig the mixer enough headroom
        engine.mainMixerNode.outputVolume = 1.0

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
        for node in voices { node.stop() }   //R
        activeVoice = [:]                    //R
        keyVoices = []                       //R
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
        fire(buf, as: .key(index), isKeySample: true)   //R
    }

    func playGong() {
        guard started, let buf = gongBuffer else { return }
        fire(buf, as: .gong)   //R
    }

    func playKempur() {
        guard started, let buf = kempurBuffer else { return }
        fire(buf, as: .kempur)   //R
    }

    func playKemong() {
        guard started, let buf = kemongBuffer else { return }
        fire(buf, as: .kemong)   //R
    }

    /// Silence the gangsa demo samples without touching the colotomic layer.
    /// Called when the example hands over to "Your turn" so a 2s key sample
    /// doesn't keep ringing while the player is meant to be playing it.
    func stopKeySamples() {                                              //R
        guard started else { return }                                    //R
        for node in voices where keyVoices.contains(ObjectIdentifier(node)) {  //R
            node.stop()                                                  //R
        }                                                                //R
        keyVoices = []                                                   //R
        activeVoice = activeVoice.filter {                               //R
            if case .key = $0.key { return false } else { return true }  //R
        }                                                                //R
    }                                                                    //R

    /// Take the next node from the pool and start `buffer` on it now.
    private func fire(_ buffer: AVAudioPCMBuffer, as voice: Voice, isKeySample: Bool = false) {  //R
        guard !voices.isEmpty else { return }                            //R
        let node = voices[nextVoice]                                     //R
        nextVoice = (nextVoice + 1) % voices.count                       //R

        //R A gong/kemong re-strike damps its own previous ring, as on the real
        //R instrument — and stops two copies of an 8s gong overlapping.
        if let previous = activeVoice[voice], previous !== node {         //R
            previous.stop()                                              //R
            keyVoices.remove(ObjectIdentifier(previous))                 //R
        }                                                                //R

        node.stop()   //R clears whatever this recycled node was still playing
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)  //R
        node.play()                                                      //R

        activeVoice[voice] = node                                        //R
        if isKeySample { keyVoices.insert(ObjectIdentifier(node)) }       //R
        else { keyVoices.remove(ObjectIdentifier(node)) }                //R
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
        return trimLeadingSilence(buf)   //R
    }

    //R --------------------------------------------------------------------
    //R Several bundled samples were recorded with the strike well into the file
    //R — key4 at 247ms, key3 at 620ms, key7 at 870ms, kemong at 23ms. Playing
    //R them from frame 0 put the audible attack that far behind the visual cue.
    //R Trim the lead-in at load time so frame 0 of every buffer IS the attack.
    //R --------------------------------------------------------------------
    private func trimLeadingSilence(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {  //R
        guard let source = buffer.floatChannelData else { return buffer }
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        guard frames > 0, channels > 0 else { return buffer }

        var peak: Float = 0
        for c in 0..<channels {
            for i in 0..<frames { peak = max(peak, abs(source[c][i])) }
        }
        guard peak > 0 else { return buffer }

        // 8% of peak clears the room tone ahead of the strike on every sample
        // while still landing on the leading edge of the transient.
        let threshold = peak * 0.08
        var onset = 0
        search: for i in 0..<frames {
            for c in 0..<channels where abs(source[c][i]) >= threshold {
                onset = i
                break search
            }
        }
        // Keep a couple of ms of pre-roll so the transient isn't clipped flat.
        onset = max(0, onset - Int(buffer.format.sampleRate * 0.002))
        guard onset > 0 else { return buffer }

        let length = AVAudioFrameCount(frames - onset)
        guard let trimmed = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: length),
              let destination = trimmed.floatChannelData
        else { return buffer }
        trimmed.frameLength = length
        for c in 0..<channels {
            destination[c].update(from: source[c] + onset, count: Int(length))
        }
        return trimmed
    }
}

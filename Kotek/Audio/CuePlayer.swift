//
//  CuePlayer.swift
//  Kotek
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
    private var kajarBuffer: AVAudioPCMBuffer?

    //R --------------------------------------------------------------------
    //R Voice pool.
    //R
    //R Previously each sound owned ONE AVAudioPlayerNode and every cue called
    //R scheduleBuffer(at: nil) on it. On an already-playing node that APPENDS to
    //R the node's queue — the buffer starts only after everything before it has
    //R finished. The samples are long (key* 2s, kajar 3s, gong 8s) and the cues
    //R come fast (a key every ~230ms, a kajar every ~1.9s, a gong every 7.5s),
    //R so each sound fell further and further behind its own visual cue and kept
    //R sounding long after the example was over. Hence: gong not matching the
    //R circle, gangsa not matching the bilah, gangsa still ringing in "Your turn".
    //R
    //R Now every cue takes the next free node out of a pool and starts it
    //R immediately, so a cue always sounds on the frame it was asked for.
    //R --------------------------------------------------------------------
    private enum Voice: Hashable { case key(Int), gong, kempur, kajar }  //R
    private let voiceCount = 12                                          //R
    private var voices: [AVAudioPlayerNode] = []                         //R

    //R --------------------------------------------------------------------
    //R Every bundled sample peaks at 0.708 (-3 dBFS), so any TWO sounding at
    //R once already exceed full scale — and a dense passage routinely stacks
    //R four (your half, your partner's, kajar on the beat, gong on the cycle).
    //R The mixer was left at 1.0 under a comment claiming headroom it did not
    //R actually give, so the sum clipped: that square-wave crunch is what makes
    //R the output "explode" rather than simply sound loud.
    //R
    //R A peak limiter across the pool catches the overs and leaves everything
    //R below the threshold untouched, so a single strike sounds exactly as it
    //R did before — the gangsa and gong tone stays as recorded.
    //R
    //R The submix is not decoration. An effect node has a SINGLE input bus, so
    //R connecting the pool straight to the limiter made each connect() evict the
    //R one before it — eleven voices ended up dangling and fire() tripped
    //R "player started when in a disconnected state". A mixer takes many inputs;
    //R the limiter takes its one summed signal from that.
    //R --------------------------------------------------------------------
    private let submix = AVAudioMixerNode()                              //R
    private let limiter = AVAudioUnitEffect(                             //R
        audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0))
    private var nextVoice = 0                                            //R
    /// Node currently carrying each source, so a re-strike cuts its own ring.
    private var activeVoice: [Voice: AVAudioPlayerNode] = [:]            //R
    /// Nodes carrying gangsa samples, so the example can be silenced wholesale.
    private var keyVoices: Set<ObjectIdentifier> = []                    //R

    func start() {
        guard !started else { return }

        //R The audio session is NOT configured here any more. See below.

        //R Decoding moved to SampleLibrary, which the splash screen warms off
        //R the main thread. This used to read and scan thirteen WAVs right here,
        //R on the main actor, the first time a session started — which is what
        //R the pause before the first sound was.
        let samples = SampleLibrary.shared
        for i in 0..<10 { keyBuffers[i] = samples.buffer("key\(i)") }
        gongBuffer = samples.buffer("gong")
        kempurBuffer = samples.buffer("kempur")
        kajarBuffer = samples.buffer("kajar")

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        //R All bundled samples share one processing format, so one pool serves
        //R every recorded cue.
        let sampleFormat = keyBuffers[0]?.format ?? gongBuffer?.format ?? format
        //R The pool sums in the submix, and only that one signal hits the limiter.
        engine.attach(submix)                                            //R
        engine.attach(limiter)                                           //R
        engine.connect(submix, to: limiter, format: sampleFormat)        //R
        engine.connect(limiter, to: engine.mainMixerNode, format: sampleFormat)  //R
        voices = (0..<voiceCount).map { _ in AVAudioPlayerNode() }
        for node in voices {
            engine.attach(node)
            engine.connect(node, to: submix, format: sampleFormat)       //R
        }

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
    
    //R --------------------------------------------------------------------
    //R This used to call `setCategory` + `setActive` itself, which made TWO
    //R owners of one shared audio session — here and AudioSessionManager — with
    //R slightly different options (.mixWithOthers vs .allowBluetoothA2DP).
    //R
    //R That is not merely untidy. Reconfiguring an ACTIVE session pulls the rug
    //R from under an AVAudioEngine that already has a microphone tap installed:
    //R the input goes silent while `isRunning` stays true, so nothing errors and
    //R nothing logs — strike detection simply stops hearing anything.
    //R
    //R It only surfaced when the ear started being brought up on the demo screen
    //R rather than on the way into the run. Before that the cue player happened
    //R to configure the session FIRST and the tap was installed after it, so the
    //R order was accidentally correct. Moving one call inverted it, and the
    //R detection test screen — which never starts a cue player — went on working
    //R perfectly, which is exactly what made it look like a play-loop problem.
    //R
    //R AudioSessionManager owns the session. Nothing else touches it.
    //R --------------------------------------------------------------------

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

    /// A gangsa key. `pan` places the voice in the stereo field — your own half
    /// on one side, your partner's on the other, the way two players sit facing
    /// each other across the pair (§7).
    func playKeySample(index: Int, pan: Float = 0, volume: Float = 1) {
        guard started, let buf = keyBuffers[index] else { return }
        fire(buf, as: .key(index), isKeySample: true, pan: pan, volume: volume)   //R
    }

    func playGong() {
        guard started, let buf = gongBuffer else { return }
        fire(buf, as: .gong)   //R
    }

    func playKempur() {
        guard started, let buf = kempurBuffer else { return }
        fire(buf, as: .kempur)   //R
    }

    func playKajar() {
        guard started, let buf = kajarBuffer else { return }
        fire(buf, as: .kajar)   //R
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

    /// Silence the colotomic layer without touching the gangsa. A gong rings for
    /// eight seconds, so muting it mid-stroke has to cut the one already sounding
    /// or the switch appears not to work.
    func stopColotomic() {                                               //R
        guard started else { return }                                    //R
        for (voice, node) in activeVoice {                               //R
            if case .key = voice { continue }                            //R
            node.stop()                                                  //R
        }                                                                //R
        activeVoice = activeVoice.filter {                               //R
            if case .key = $0.key { return true } else { return false }  //R
        }                                                                //R
    }                                                                    //R

    /// Take the next node from the pool and start `buffer` on it now.
    private func fire(_ buffer: AVAudioPCMBuffer, as voice: Voice, isKeySample: Bool = false,
                      pan: Float = 0, volume: Float = 1) {               //R
        guard !voices.isEmpty else { return }                            //R
        let node = voices[nextVoice]                                     //R
        nextVoice = (nextVoice + 1) % voices.count                       //R

        //R A gong/kajar re-strike damps its own previous ring, as on the real
        //R instrument — and stops two copies of an 8s gong overlapping.
        if let previous = activeVoice[voice], previous !== node {         //R
            previous.stop()                                              //R
            keyVoices.remove(ObjectIdentifier(previous))                 //R
        }                                                                //R

        node.stop()   //R clears whatever this recycled node was still playing
        //R Nodes are recycled, so placement is set on every fire, never once.
        node.pan = pan                                                   //R
        node.volume = volume                                             //R
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
}

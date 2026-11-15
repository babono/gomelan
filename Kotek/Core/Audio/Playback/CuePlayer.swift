//
//  CuePlayer.swift
//  Kotek
//
//  The audio cue layer (PRD §5.4). Because the screen is small and the player
//  stands over the instrument, audio carries as much guidance as vision:
//
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
    /// The gangsa whose recorded keys `start()` should sound; nil or a key
    /// without a recording keeps the bundled sample.
    var instrumentID: String?

    // Recorded-sample playback (demo pattern, colotomic layer)
    private var keyBuffers: [Int: AVAudioPCMBuffer] = [:]
    private var gongBuffer: AVAudioPCMBuffer?
    private var kempurBuffer: AVAudioPCMBuffer?
    private var klentongBuffer: AVAudioPCMBuffer?
    private var kajarBuffer: AVAudioPCMBuffer?

    /// R --------------------------------------------------------------------
    /// R Voice mixer.
    /// R
    /// R Previously each sound owned ONE AVAudioPlayerNode and every cue called
    /// R scheduleBuffer(at: nil) on it. On an already-playing node that APPENDS to
    /// R the node's queue — the buffer starts only after everything before it has
    /// R finished. The samples are long (key* 2s, kajar 3s, gong 8s) and the cues
    /// R come fast, so each sound fell further and further behind its visual cue.
    /// R A pool of nodes fixed that, but a node can only be stopped dead, and a
    /// R dead stop of a ringing bass sample is a thump; ramping node.volume from a
    /// R timer just moved the thump onto the ticks. CueMixer sums the samples in
    /// R one source node and fades per sample on the audio thread, so a retrigger
    /// R or a mute is a 20 ms ramp, never a cut.
    /// R --------------------------------------------------------------------
    private var mixer: CueMixer? // R

    /// `partnerKey`: the other half's bilah, its own source so damping one
    /// player's stroke never stops the other's on the same bilah — two
    /// gangsa, two hands.
    private enum Voice { case key(Int), partnerKey(Int), gong, kempur, klentong, kajar } // R

    /// What a re-strike replaces: each key, and each colotomic sound, is its own.
    private func play(_ buffer: AVAudioPCMBuffer, as voice: Voice, pan: Float = 0, volume: Float = 1) { // R
        let source: Int
        let group: CueMixer.Group
        switch voice {
        case let .key(i): (source, group) = (i, .key)
        case let .partnerKey(i): (source, group) = (Self.partnerSource + i, .key)
        case .gong: (source, group) = (100, .colotomic)
        case .kempur: (source, group) = (101, .colotomic)
        case .klentong: (source, group) = (102, .colotomic)
        case .kajar: (source, group) = (103, .colotomic)
        }
        mixer?.play(buffer, source: source, group: group, pan: pan, volume: volume)
    }

    /// R --------------------------------------------------------------------
    /// R Every bundled sample peaks near full scale, so any TWO sounding at once
    /// R exceed it — and a dense passage routinely stacks four (your half, your
    /// R partner's, kajar on the beat, gong on the cycle). Summed unchecked that
    /// R clips: a square-wave crunch that makes the output "explode". A peak
    /// R limiter after the mixer catches the overs and leaves a single strike
    /// R exactly as recorded.
    /// R --------------------------------------------------------------------
    private let limiter = AVAudioUnitEffect( // R
        audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        ))
    private var wired = false // R

    func start() {
        guard !started else { return }

        // R The audio session is NOT configured here any more. See below.

        // R Decoding moved to SampleLibrary, which the splash screen warms off
        // R the main thread. This used to read and scan thirteen WAVs right here,
        // R on the main actor, the first time a session started — which is what
        // R the pause before the first sound was.
        let samples = SampleLibrary.shared
        for i in 0 ..< 10 {
            keyBuffers[i] = samples.buffer("key\(i)")
        }

        // R All bundled samples share one processing format, so one pool serves
        // R every recorded cue. Taken BEFORE the player's own recordings go in:
        // R they are written at the mic's rate, and the pool stays wired for
        // R the bundled one.
        let sampleFormat = keyBuffers[0]?.format ?? format
        /// The colotomic samples were not recorded alike (gong and kempur stereo,
        /// klentong 16 kHz, kajar 44.1 kHz) and the pool is wired for the keys'
        /// format, so each is brought to it here.
        func pooled(_ name: String) -> AVAudioPCMBuffer? {
            samples.buffer(name).flatMap { SampleLibrary.convert($0, to: sampleFormat) }
        }
        gongBuffer = pooled("gong")
        kempurBuffer = pooled("kempur")
        klentongBuffer = pooled("klentong")
        kajarBuffer = pooled("kajar")
        // ponytail: decoded here on the main actor, ten short clips; move into
        // SampleLibrary's warm-up if the pause before the first cue is audible.
        if let instrumentID {
            for i in 0 ..< 10 {
                if let clip = NoteClipCapture.latestClip(instrumentID: instrumentID, keyIndex: i),
                   let buffer = SampleLibrary.decodeRecording(clip, as: sampleFormat)
                {
                    keyBuffers[i] = buffer
                }
            }
        }

        // R Wired once: the source node and limiter survive engine.stop(), and
        // R re-attaching them on every start leaked a node set per session.
        if !wired {
            let mixer = CueMixer(sampleRate: sampleFormat.sampleRate)
            let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleFormat.sampleRate, channels: 2)!
            let node = mixer.makeNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.attach(node)
            engine.attach(limiter)
            engine.connect(node, to: limiter, format: stereo)
            engine.connect(limiter, to: engine.mainMixerNode, format: stereo)
            self.mixer = mixer
            wired = true
        }
        // Voices left frozen by a stopped engine would resume with it.
        if !engine.isRunning { mixer?.clear() }

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
        // R Stopping the engine with a gong ringing cuts it mid-waveform — a thump.
        // R `started` goes false now so no new cue can start, the voices fade, and
        // R the engine stops once they are silent. A start() in between wins.
        started = false // R
        player.stop()
        mixer?.fade(nil) // R
        Task { // R
            try? await Task.sleep(for: .seconds(CueMixer.fadeSeconds * 2)) // R
            if !started { engine.stop() } // R
        } // R
    }

    // R --------------------------------------------------------------------
    // R This used to call `setCategory` + `setActive` itself, which made TWO
    // R owners of one shared audio session — here and AudioSessionManager — with
    // R slightly different options (.mixWithOthers vs .allowBluetoothA2DP).
    // R
    // R That is not merely untidy. Reconfiguring an ACTIVE session pulls the rug
    // R from under an AVAudioEngine that already has a microphone tap installed:
    // R the input goes silent while `isRunning` stays true, so nothing errors and
    // R nothing logs — strike detection simply stops hearing anything.
    // R
    // R It only surfaced when the ear started being brought up on the demo screen
    // R rather than on the way into the run. Before that the cue player happened
    // R to configure the session FIRST and the tap was installed after it, so the
    // R order was accidentally correct. Moving one call inverted it, and the
    // R detection test screen — which never starts a cue player — went on working
    // R perfectly, which is exactly what made it look like a play-loop problem.
    // R
    // R AudioSessionManager owns the session. Nothing else touches it.
    // R --------------------------------------------------------------------

    /// Whether the engine is genuinely producing audio, restarting it if it
    /// quietly stopped.
    ///
    /// `started` is our flag and it does not know about interruptions. Send the
    /// app to the background with a preview or a session running and iOS pulls
    /// the audio session out; the engine stops, `started` stays true, and the
    /// first cue after you come back calls play() on a node whose engine has no
    /// IO cycle. That raises "player did not see an IO cycle" — an NSException,
    /// which Swift cannot catch, so it takes the app with it. Every path that
    /// touches a node goes through here.
    private func ensureLive() -> Bool {
        guard started else { return false }
        if engine.isRunning { return true }
        do {
            try engine.start()
            player.play()
            return true
        } catch {
            // R Give up rather than retry every frame: the screen will stop and
            // R restart us, and a failed start sixty times a second is worse than
            // R silence.
            print("[CuePlayer] engine would not restart: \(error)")
            started = false
            return false
        }
    }

    // MARK: - Cues

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
    func playKeySample(index: Int, pan: Float = 0, volume: Float = 1, partner: Bool = false) {
        guard ensureLive(), let buf = keyBuffers[index] else { return }
        play(buf, as: partner ? .partnerKey(index) : .key(index), pan: pan, volume: volume) // R
    }

    /// The hand stopping a bilah: what `playKeySample` left ringing on it
    /// dies away (`CueMixer.dampSeconds`). Without it every stroke rang its
    /// whole sample, two seconds, through the damp the waterfall showed.
    func dampKey(index: Int, partner: Bool = false) {
        guard started, engine.isRunning else { return }
        mixer?.damp(source: (partner ? Self.partnerSource : 0) + index)
    }

    /// Where the partner's bilah sources start; clear of the keys and the
    /// colotomic sounds (100…103).
    private static let partnerSource = 200

    func playGong() {
        guard ensureLive(), let buf = gongBuffer else { return }
        play(buf, as: .gong) // R
    }

    func playKempur() {
        guard ensureLive(), let buf = kempurBuffer else { return }
        play(buf, as: .kempur) // R
    }

    func playKlentong() {
        guard ensureLive(), let buf = klentongBuffer else { return }
        play(buf, as: .klentong)
    }

    func playKajar() {
        guard ensureLive(), let buf = kajarBuffer else { return }
        play(buf, as: .kajar) // R
    }

    /// Silence the gangsa demo samples without touching the colotomic layer.
    /// Called when the example hands over to "Your turn" so a 2s key sample
    /// doesn't keep ringing while the player is meant to be playing it.
    func stopKeySamples() { // R
        guard started, engine.isRunning else { return } // R
        mixer?.fade(.key) // R
    } // R

    /// Silence the colotomic layer without touching the gangsa. A gong rings for
    /// eight seconds, so muting it mid-stroke has to fade the one already
    /// sounding or the switch appears not to work.
    func stopColotomic() { // R
        guard started, engine.isRunning else { return } // R
        mixer?.fade(.colotomic) // R
    } // R

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
        guard ensureLive() else { return }
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
        for i in 0 ..< n {
            let phase = 2 * Double.pi * frequency * Double(i) / sampleRate
            var env: Double = 1
            if i < attack {
                env = Double(i) / Double(max(attack, 1))
            } else if i > n - release {
                env = Double(n - i) / Double(max(release, 1))
            }
            samples[i] = Float(sin(phase) * env) * gain
        }
        return buffer
    }
}

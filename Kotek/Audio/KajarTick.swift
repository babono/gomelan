//
//  KajarTick.swift
//  Kotek
//
//  The sound a control makes when you touch it.
//
//  In a gamelan the kajar is the small held gong that ticks the pulse — the one
//  instrument whose whole job is to mark a moment rather than carry a melody.
//  That is exactly what a button press is, so the app taps the same sound: the
//  interface keeps time with the instrument it is teaching.
//
//  WHY IT IS NOT A `CuePlayer` VOICE, which is the obvious place to put it:
//  `CuePlayer` owns an `AVAudioEngine` that is started per session and stopped
//  with it, so it is silent on every screen before the first play — which is
//  most of the screens with buttons on them. This is a handful of prepared
//  `AVAudioPlayer`s instead, alive for the life of the process and belonging to
//  no session at all. Same reasoning as `TitleMusic`.
//
//  MEASURED, not assumed: `kajar.wav` puts 58% of its energy at 500 Hz and 19%
//  at 1 kHz, with almost nothing below 400. That is squarely where a phone
//  speaker works, which is why it needs none of the octave-folding `SplashChime`
//  has to do to make the kempur audible — this sample carries as recorded. Its
//  envelope is already down 40 dB by 300 ms, so the tick is the sample's own
//  decay and not a fade someone chose.
//
//  THE ONE PLACE IT IS DELIBERATELY SILENT: the baseline capture button in
//  `CalibrationView`. That button starts the microphone learning what a real
//  strike on this gangsa sounds like, and its own tick would still be ringing
//  inside the first window it records — the app would teach itself that a
//  button press is a strike. It stays `.plain`; see the comment there.
//

import AVFoundation

/// Main-actor isolated, like everything else in this target. That is the whole
/// synchronisation story: taps arrive on the main thread, so the round-robin
/// below needs no lock.
final class KajarTick {
    static let shared = KajarTick()

    /// Strike the tick. The call every control makes.
    static func strike() { shared.strike() }

    // MARK: - Tuning

    /// How much of the sample the tick keeps. The recording is 1.64 s but has
    /// spent its energy by 300 ms; the rest is a tail nobody hears and four
    /// copies of it sitting in memory.
    private static let tickDuration: TimeInterval = 0.32

    /// A ramp over the last few ms of the truncation. Not a musical fade — the
    /// cut lands where the signal is already tiny, and this only stops it
    /// landing on a non-zero sample, which is a click.
    private static let fadeDuration: TimeInterval = 0.02

    /// Level. The signal is normalised to just under full scale so it survives
    /// `.measurement` mode — which exists to defeat the processing that makes
    /// quiet material carry, and costs output level for it (see
    /// `AudioSessionManager`) — and then this takes it back down to where a
    /// button belongs: present, under the instrument, not competing with it.
    private static let level: Float = 0.5

    /// Enough voices that a fast double-tap overlaps rather than cutting
    /// itself off, and few enough that a stuck finger cannot build a drone.
    private static let voiceCount = 4

    // MARK: - Voices

    private var voices: [AVAudioPlayer] = []
    private var next = 0
    private var isWarm = false

    private init() {}

    /// Build the voices now rather than on the first tap.
    ///
    /// Called from `Preloader` behind the splash. Idempotent, and `strike()`
    /// calls it too — so a missed warm-up is a slightly late first tick, never
    /// a silent one.
    func warm() {
        guard !isWarm else { return }
        isWarm = true

        guard let wav = Self.tick else {
            print("[KajarTick] could not build the tick from kajar.wav")
            return
        }
        voices = (0..<Self.voiceCount).compactMap { _ in
            guard let player = try? AVAudioPlayer(data: wav) else { return nil }
            player.volume = Self.level
            // Prepared once, here. This is the part with the latency in it, and
            // doing it per tap is what would put the tick behind the finger.
            player.prepareToPlay()
            return player
        }
    }

    /// Sound one tick, immediately.
    ///
    /// Takes the next voice round-robin rather than restarting one player,
    /// for the same reason `CuePlayer` has a pool: a second call on a playing
    /// `AVAudioPlayer` has to stop it first, and a stopped-and-restarted tick
    /// is audibly a stutter where two overlapping ones are just two taps.
    func strike() {
        warm()
        guard !voices.isEmpty else { return }

        let voice = voices[next]
        next = (next + 1) % voices.count

        // `pause()`, not `stop()`: stop() tears down what prepareToPlay() set
        // up, so the voice would pay that cost again on its next turn.
        voice.pause()
        voice.currentTime = 0
        voice.play()
    }

    // MARK: - Building the tick

    /// The shortened, normalised kajar as a WAV in memory. Built once for the
    /// process; all four voices play the same bytes.
    private static let tick: Data? = buildTick()

    private static func buildTick() -> Data? {
        // Already decoded and trimmed to its attack by the preloader, so this
        // is a lookup — and `trimLeadingSilence` is why frame 0 below is the
        // strike rather than 23 ms of room tone ahead of it.
        guard let source = SampleLibrary.shared.buffer("kajar"),
              let channel = source.floatChannelData else { return nil }

        let sampleRate = source.format.sampleRate
        let count = min(Int(source.frameLength), Int(sampleRate * tickDuration))
        guard count > 0 else { return nil }

        var tick = Array(UnsafeBufferPointer(start: channel[0], count: count))

        // Normalise: the recording peaks at 0.52, and starting from full scale
        // is what leaves `level` somewhere to work from.
        var peak: Float = 0
        for value in tick { peak = max(peak, abs(value)) }
        guard peak > 0 else { return nil }
        let scale = 0.97 / peak
        for i in 0..<count { tick[i] *= scale }

        let fade = min(count, Int(sampleRate * fadeDuration))
        if fade > 1 {
            for i in (count - fade)..<count {
                tick[i] *= Float(count - i) / Float(fade)
            }
        }

        return PCMWav.encode(tick, sampleRate: Int(sampleRate))
    }
}

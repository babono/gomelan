//
//  SplashChime.swift
//  Kotek
//
//  The single kempur stroke that opens the app, under the splash screen.
//
//  A kempur is what marks a phrase boundary in the gamelan — it is the sound of
//  something beginning. One stroke, allowed to ring, faded out as the splash
//  hands over to the landing screen.
//
//  THE PROBLEM THIS SOLVES, because it is not obvious from the code:
//
//  `kempur.wav` is very nearly a pure 125 Hz tone. Measured, not assumed: its
//  second partial at 250 Hz is already 12 dB down, and there is nothing at all
//  above 400 Hz — every band up there sits 85 dB or more below the fundamental.
//  Its RMS is a perfectly healthy -13.8 dBFS, so the file is not quiet; it is
//  LOW. A phone speaker has almost no acoustic output below about 500 Hz, so on
//  an iPhone this sample is close to inaudible however it is played.
//
//  That is why nothing about level fixed it. Full volume did not, because the
//  driver cannot move air at 125 Hz whatever it is sent. Ducking the music did
//  not, because the gong was not being masked — it was never arriving. And
//  layering octave-shifted copies via `AVAudioPlayer.rate` did not, because
//  that property only accepts 0.5…2.0, so the ×4 voice — the one carrying the
//  500 Hz and 1 kHz content that was the entire point — was silently clamped.
//
//  So the signal is built here instead, where nothing is clamped: the stroke is
//  folded up into octaves the speaker can actually reproduce, saturated to lift
//  its density, normalised to full scale, and handed to `AVAudioPlayer` as a
//  WAV in memory. Same proven playback path, a signal that can be heard.
//
//  The original recording is never modified. `CuePlayer` plays that same sample
//  in the colotomic layer during a session, where its level is balanced against
//  a peak limiter, and a hotter kempur there would change the gameplay mix.
//

import AVFoundation

/// Main-actor isolated (this target's default). `TitleMusic` is `nonisolated`,
/// which is the one intentional difference: staying on the main actor is what
/// lets the ring and fade be scheduled without handing a non-`Sendable`
/// `AVAudioPlayer` across an isolation boundary.
final class SplashChime {

    private var player: AVAudioPlayer?
    /// Struck once per launch, ever — including across a trip to the background
    /// and back, which must not sound the gong again over the landing screen.
    private var hasStruck = false

    /// How long the stroke owns the room: full ring, then the fall.
    ///
    /// Published so the title music can duck underneath for exactly this long
    /// and swell afterwards, rather than both guessing at a number and drifting
    /// apart the first time either is adjusted.
    static let ringDuration: TimeInterval = 2.0
    static let fadeDuration: TimeInterval = 0.8
    static var totalDuration: TimeInterval { ringDuration + fadeDuration }

    // MARK: - Striking

    /// Strike it: sound now, ring, then fade.
    ///
    /// - Parameters:
    ///   - gain: final level, 0…1. The signal is already normalised to just
    ///     under full scale, so this only ever takes away.
    ///   - ringFor: how long it sounds before the fade starts. Matched to the
    ///     splash's minimum duration, so the fall lands with the hand-over.
    ///   - fade: how long the fall takes. A gong cut off dead reads as a
    ///     glitch; one still falling as the screen changes reads as one moment.
    func strike(gain: Float = 1.0,
                ringFor: TimeInterval = SplashChime.ringDuration,
                fade: TimeInterval = SplashChime.fadeDuration) {
        guard !hasStruck else { return }
        hasStruck = true

        guard let wav = Self.audibleStroke else {
            print("[SplashChime] could not build the stroke from kempur.wav")
            return
        }

        // Activating an already-active session is a no-op, so this costs
        // nothing and covers the case where it is not active yet.
        try? AVAudioSession.sharedInstance().setActive(true)

        do {
            let player = try AVAudioPlayer(data: wav)
            player.volume = gain
            player.prepareToPlay()
            // No fade in. This is a struck instrument — the attack IS the
            // sound, and easing into it would turn a stroke into a swell.
            guard player.play() else {
                let session = AVAudioSession.sharedInstance()
                print("""
                      [SplashChime] play() refused. \
                      category=\(session.category.rawValue) \
                      mode=\(session.mode.rawValue) \
                      outputVolume=\(session.outputVolume)
                      """)
                return
            }
            self.player = player
            scheduleFade(after: ringFor, over: fade)
        } catch {
            print("[SplashChime] could not play the stroke: \(error)")
        }
    }

    /// Let it ring, then fall.
    ///
    /// The player is held strongly and released only once the fade has landed:
    /// it has to outlive the splash screen that started it, or the very
    /// transition the fade exists to smooth over is what cuts it off.
    private func scheduleFade(after ring: TimeInterval, over fade: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(ring))
            guard let player else { return }
            player.setVolume(0, fadeDuration: fade)
            try? await Task.sleep(for: .seconds(fade))
            player.stop()
            self.player = nil
        }
    }

    deinit { player?.stop() }

    // MARK: - Building a stroke a phone can reproduce

    /// How much of each octave goes into the mix.
    ///
    /// `step` is a decimation factor: taking every Nth sample of a signal and
    /// playing it back at the original rate is that signal N times higher. The
    /// source is band-limited to ~400 Hz, so even ×8 lands at 1 kHz — nowhere
    /// near the 22 kHz Nyquist — and there is no aliasing to guard against.
    ///
    /// The weights climb with pitch on purpose. The fundamental is kept because
    /// on headphones it is the real sound and does the work the upper octaves
    /// only imply, but on a phone it contributes nothing audible, so the octaves
    /// that a small driver CAN reproduce are the ones carrying the level. All
    /// are harmonics of the same tone, so the ear fuses them into one gong and
    /// infers the pitch from the series — the stroke still reads as a kempur.
    private static let octaves: [(step: Int, gain: Float)] = [
        (1, 0.30),   //  125 Hz — the true tone, for headphones
        (2, 0.45),   //  250 Hz
        (4, 0.90),   //  500 Hz — a phone speaker starts working here
        (8, 0.70),   // 1000 Hz — and is at its most efficient here
    ]

    /// How hard the sum is driven into saturation before normalising.
    ///
    /// A gong is nearly all sustain: this one's RMS sits 11 dB under its peak,
    /// so normalising alone would set the loudest instant to full scale and
    /// leave everything after it quiet. Soft saturation pulls the body up
    /// towards the peak — and, because it is a non-linearity, adds further
    /// harmonics of its own, which here is a second helping of exactly what the
    /// speaker needs. `tanh` because it compresses smoothly and never clips.
    private static let drive: Float = 2.6

    /// The stroke, as a 16-bit WAV in memory.
    ///
    /// Built once and kept: the gong is struck exactly once per launch, but
    /// `@State` can construct several `SplashChime`s while SwiftUI settles, and
    /// there is no reason for each to redo the arithmetic.
    private static let audibleStroke: Data? = buildAudibleStroke()

    private static func buildAudibleStroke() -> Data? {
        // Already decoded and trimmed by the preloader, so this is a lookup.
        guard let source = SampleLibrary.shared.buffer("kempur"),
              let channel = source.floatChannelData else { return nil }

        let count = Int(source.frameLength)
        guard count > 0 else { return nil }
        let input = UnsafeBufferPointer(start: channel[0], count: count)

        // Fold the octaves together. Each shifted copy is shorter than the last
        // — an octave up is half the duration — so the high partials die away
        // first and the low tone is left ringing, which is what a struck gong
        // does anyway.
        var mixed = [Float](repeating: 0, count: count)
        for (step, gain) in octaves {
            var read = 0
            var write = 0
            while read < count {
                mixed[write] += input[read] * gain
                read += step
                write += 1
            }
        }

        // Saturate, then normalise to just under full scale.
        var peak: Float = 0
        for i in 0..<count {
            let saturated = tanhf(mixed[i] * drive)
            mixed[i] = saturated
            peak = max(peak, abs(saturated))
        }
        guard peak > 0 else { return nil }
        let scale = 0.97 / peak
        for i in 0..<count { mixed[i] *= scale }

        return PCMWav.encode(mixed, sampleRate: Int(source.format.sampleRate))
    }
}

//
//  TitleMusic.swift
//  Kotek
//
//  The gamelan playing behind the title screen, and stopping when you go in.
//
//  Deliberately an `AVAudioPlayer` rather than another node on CuePlayer's
//  engine. That engine is tuned for the play loop — a voice pool feeding a
//  submix and a limiter, with a `.measurement` session that exists to keep the
//  microphone honest — and threading a ninety-second music bed through it would
//  put background audio inside the path that strike detection depends on. This
//  is a separate, disposable object with no relationship to any of it.
//
//  It fades rather than cuts. The title screen hands over to a camera and a
//  count-in; a hard stop on the same frame as the transition reads as a glitch,
//  where half a second of fall lets the room change.
//

import AVFoundation

nonisolated final class TitleMusic {

    private var player: AVAudioPlayer?
    /// Guards against a fade already in flight when the view disappears — the
    /// screen can be left by the button and by navigation at nearly the same
    /// moment, and stopping twice would cut the tail the fade exists to give.
    private var isFading = false

    /// Start looping, from the top. Safe to call when already playing.
    func start(volume: Float = 1.0) {
        guard player == nil else { return }
        guard let url = Bundle.main.url(forResource: "bgm", withExtension: "m4a") else {
            print("[TitleMusic] bgm.m4a missing from the bundle")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            player.play()
            // Fade UP too. The screen appears with a navigation animation and
            // music arriving at full level on the same frame sounds like a
            // mistake rather than an entrance.
            player.setVolume(volume, fadeDuration: 1.2)
            self.player = player
            isFading = false
        } catch {
            print("[TitleMusic] could not play bgm.m4a: \(error)")
        }
    }

    /// Fade out and release. Idempotent.
    func stop(fadeDuration: TimeInterval = 0.6) {
        guard let player, !isFading else { return }
        isFading = true
        player.setVolume(0, fadeDuration: fadeDuration)
        // Held until the fade lands, then released. Referenced strongly on
        // purpose: this must outlive the view that started it, or the fade is
        // cut short by the very transition it is smoothing over.
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration) {
            player.stop()
        }
        self.player = nil
    }

    deinit { player?.stop() }
}

//
//  SampleLibrary.swift
//  Kotek
//
//  The thirteen bundled samples — ten gangsa keys, gong, kempur, kajar —
//  decoded once for the whole process.
//
//  This exists because `CuePlayer.start()` used to do the decoding, and
//  `CuePlayer` is main-actor isolated like everything else in this target. So
//  the first time a session started, the main thread read thirteen WAVs off
//  disk, allocated a PCM buffer for each, and then walked every sample of every
//  one of them TWICE — once to find the peak, once to find the attack (see
//  `trimLeadingSilence`). That is a few hundred milliseconds of arithmetic on
//  the thread that is supposed to be drawing, which is the pause you get
//  between pressing play and hearing anything.
//
//  Nothing about that work is per-session: the same thirteen files decode to
//  the same thirteen buffers every time. So it happens once, off the main
//  thread, while the splash screen is up — and `CuePlayer.start()` becomes a
//  dictionary lookup.
//
//  `nonisolated` on purpose: the whole point is to be fillable from a
//  background task. The lock is what makes that safe, and it is uncontended in
//  practice — the preloader writes once at launch and every later caller only
//  reads.
//

import AVFoundation

nonisolated final class SampleLibrary {
    static let shared = SampleLibrary()

    /// Every sample the app ships, in the order the preloader warms them.
    /// Keys first: they are the ones a session cannot start without.
    static let allNames: [String] =
        (0..<10).map { "key\($0)" } + ["gong", "kempur", "kajar"]

    private let lock = NSLock()
    private var cache: [String: AVAudioPCMBuffer] = [:]

    private init() {}

    /// The decoded, silence-trimmed buffer for a bundled sample.
    ///
    /// Decodes on the calling thread if it has to, so a cache miss is never a
    /// missing sound — it is just the old, slow behaviour for that one file.
    func buffer(_ name: String) -> AVAudioPCMBuffer? {
        lock.lock()
        if let hit = cache[name] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        // Decoded OUTSIDE the lock: this is the expensive part, and holding the
        // lock across it would serialise the preloader's warm-up behind itself.
        guard let decoded = Self.decode(name) else { return nil }

        lock.lock()
        // Another thread may have won the race. Either buffer is equally valid;
        // keeping the one already published means callers that have it keep a
        // buffer identical to the one everyone else sees.
        let stored = cache[name] ?? decoded
        cache[name] = stored
        lock.unlock()
        return stored
    }

    /// Whether a sample is already decoded — lets the caller tell a warm cache
    /// from a cold one without paying for a decode to find out.
    func isWarm(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cache[name] != nil
    }

    // MARK: - Decoding

    private static func decode(_ name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url),
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                         frameCapacity: AVAudioFrameCount(file.length))
        else {
            print("[SampleLibrary] missing sample: \(name).wav — check it's in Resources and the target")
            return nil
        }
        try? file.read(into: buf)
        return trimLeadingSilence(buf)
    }

    // Several bundled samples were recorded with the strike well into the file
    // — key4 at 247ms, key3 at 620ms, key7 at 870ms, kajar at 23ms. Playing
    // them from frame 0 put the audible attack that far behind the visual cue.
    // Trim the lead-in at load time so frame 0 of every buffer IS the attack.
    private static func trimLeadingSilence(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
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

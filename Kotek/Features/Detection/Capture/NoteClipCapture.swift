//
//  NoteClipCapture.swift
//  Kotek
//
//  Turns a raw mic take (silence, one strike, its decay) into a fixed-length
//  clip that starts at the attack, and writes it as a WAV for building audio
//  datasets (see gangsa-note-capture-spec.md).
//
//  The cut is onset threshold + FIXED duration, with no end threshold. A
//  threshold-only cut gives lengths that depend on strike strength and room
//  noise; a fixed position in the file misaligns the attack. The hybrid gives
//  clips that are both aligned and uniform.
//
//  Onset is amplitude, not spectral flux, on purpose: flux can't separate a
//  strike from handling noise (see DSPConfig), amplitude does. Padding copies
//  the room's own silence rather than writing zeros, because a jump from a
//  noisy tail to digital silence is an artifact a model learns as a shortcut.
//
//  `nonisolated`: pure sample maths and file IO, must stay off the main actor.
//

import Accelerate
import AVFoundation
import Foundation

nonisolated enum NoteClipCapture {
    enum Failure: Error, LocalizedError {
        /// Nothing in the take rose above the silence by enough, or the rise
        /// never reached the strike gate.
        case noNote
        /// The "silence" before the strike is itself as loud as a strike. Covers
        /// both a noisy room and striking inside the first 0.3 s.
        case noisyLead
        /// Less than a full clip left after the strike. Padding it out would end
        /// a ringing note in room noise, which is just another hard cut.
        case tooLate

        var errorDescription: String? {
            switch self {
            case .noNote: "No note detected, try again."
            case .tooLate: "Struck too late, try again right after \"Strike now\"."
            case .noisyLead: "Too much sound before the strike. Stay quiet for the first half second, or move somewhere quieter."
            }
        }
    }

    /// Silence the take must open with; its loudest window is the noise floor.
    /// Max rather than mean so one noise spike can't be mistaken for a strike.
    static let noiseProfileSeconds = 0.3
    static let windowSeconds = 0.01
    static let onsetFactor: Float = 4
    static let preRollWindows = 1
    /// One value for the whole dataset: changing it mid-way breaks uniformity.
    /// Bronze rings for seconds; 1.0 s left the note loud and simply stopped.
    /// ponytail: 3.0 is a starting point, retune from `Clip.endsRinging`.
    static let clipSeconds = 3.0
    static let peakTarget: Float = 0.9
    /// Only has to hide the cut on an already-quiet tail.
    static let fadeSeconds = 0.15
    /// Tail window checked for "still ringing" at the cut.
    static let tailSeconds = 0.1

    /// The user is told to strike at `strikePromptSeconds`, and has until
    /// `strikeDeadlineSeconds` to do it; the take leaves a full clip after that.
    static let strikePromptSeconds = 0.5
    static let strikeDeadlineSeconds = 1.5
    static let takeSeconds = strikeDeadlineSeconds + clipSeconds

    struct Clip {
        let samples: [Float]
        /// Peak BEFORE normalising. Normalising throws away absolute level, which
        /// the amplitude gate depends on, so it travels in the filename.
        let peak: Float
        /// The last moments were still well above the room's silence, so the
        /// cut (and fade) landed on a note that hadn't finished; raise `clipSeconds`.
        let endsRinging: Bool
    }

    /// `strikeGate` is the live detector's amplitude floor, so the tool and the
    /// game agree on what counts as a strike.
    static func extract(from x: [Float], sampleRate: Double, strikeGate: Float) throws -> Clip {
        let win = max(1, Int(sampleRate * windowSeconds))
        let noiseCount = Int(sampleRate * noiseProfileSeconds)
        let floorWindows = noiseCount / win
        let windowCount = x.count / win
        guard windowCount > floorWindows + 1 else { throw Failure.noNote }

        var rms = [Float](repeating: 0, count: windowCount)
        x.withUnsafeBufferPointer { p in
            for i in 0 ..< windowCount {
                vDSP_rmsqv(p.baseAddress! + i * win, 1, &rms[i], vDSP_Length(win))
            }
        }

        let floorRMS = rms[0 ..< floorWindows].max() ?? 0
        // RMS sits well under peak, so this only trips on a genuinely loud lead.
        if floorRMS >= strikeGate { throw Failure.noisyLead }

        // The ratio alone passes on a silent room (a tiny floor times 4 is still
        // tiny): measured noise captures land near 0.002 where strikes are 0.3+.
        // So the rise must also reach the strike gate in absolute terms.
        let threshold = floorRMS * onsetFactor
        let lookahead = win * 5
        var onset: Int?
        for i in floorWindows ..< windowCount where rms[i] > threshold {
            let from = i * win
            let to = min(x.count, from + lookahead)
            var peak: Float = 0
            x.withUnsafeBufferPointer { vDSP_maxmgv($0.baseAddress! + from, 1, &peak, vDSP_Length(to - from)) }
            if peak >= strikeGate {
                onset = i
                break
            }
        }
        guard let onset else { throw Failure.noNote }

        let start = max(0, onset - preRollWindows) * win
        let clipLength = Int(sampleRate * clipSeconds)
        guard start + clipLength <= x.count else { throw Failure.tooLate }
        var clip = Array(x[start ..< start + clipLength])

        var peak: Float = 0
        vDSP_maxmgv(clip, 1, &peak, vDSP_Length(clip.count))

        let tail = min(clip.count, Int(sampleRate * tailSeconds))
        var tailRMS: Float = 0
        clip.withUnsafeBufferPointer {
            vDSP_rmsqv($0.baseAddress! + clip.count - tail, 1, &tailRMS, vDSP_Length(tail))
        }
        let endsRinging = tailRMS > max(threshold, 1e-4)

        // Normalise first, then fade: the other way round, the fade would be
        // scaled back up by the gain.
        if peak > 0 {
            var gain = peakTarget / peak
            vDSP_vsmul(clip, 1, &gain, &clip, 1, vDSP_Length(clip.count))
        }
        let fade = min(clip.count, Int(sampleRate * fadeSeconds))
        for k in 0 ..< fade {
            clip[clip.count - fade + k] *= 1 - Float(k + 1) / Float(fade)
        }
        return Clip(samples: clip, peak: peak, endsRinging: endsRinging)
    }

    /// `Documents/NoteClips/<instrument id>/k03/k03_a0.42_<unix>.wav`, the same
    /// naming idea as TrainingCapture's crops: key index, not pitch. Per
    /// instrument, because every gangsa is tuned differently; a key's sound on
    /// one says nothing about the same index on another.
    ///
    /// A key keeps ONE recording: saving replaces the previous take, so what the
    /// screen shows and plays is always the clip that is on disk.
    static func save(_ clip: Clip, instrumentID: String, keyIndex: Int, sampleRate: Double) throws -> URL {
        let key = String(format: "k%02d", keyIndex)
        let directory = directory(instrumentID: instrumentID, keyIndex: keyIndex)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []

        let name = String(format: "%@_a%.2f_%d.wav", key, clip.peak, Int(Date().timeIntervalSince1970))
        let url = directory.appendingPathComponent(name)
        let data = PCMWav.encode(clip.samples, sampleRate: Int(sampleRate.rounded()))
        try data.write(to: url, options: .atomic)
        for old in previous { try? FileManager.default.removeItem(at: old) }
        return url
    }

    /// An instrument is gone: so are its recordings.
    static func deleteInstrument(instrumentID: String) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(instrumentID, isDirectory: true))
    }

    /// Signing out wipes the account's data from this phone, clips included.
    static func deleteAll() {
        try? FileManager.default.removeItem(at: root)
    }

    private static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NoteClips", isDirectory: true)
    }

    /// Remove a key's recording for one instrument.
    static func deleteClips(instrumentID: String, keyIndex: Int) {
        try? FileManager.default.removeItem(at: directory(instrumentID: instrumentID, keyIndex: keyIndex))
    }

    /// Peak per bin, for drawing a saved clip.
    static func waveform(of url: URL, bins: Int) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let samples = buffer.floatChannelData?[0]
        else { return [] }
        let count = Int(buffer.frameLength)
        guard count >= bins, bins > 0 else { return [] }
        let size = count / bins
        return (0 ..< bins).map { bin in
            var peak: Float = 0
            vDSP_maxmgv(samples + bin * size, 1, &peak, vDSP_Length(size))
            return peak
        }
    }

    private static func directory(instrumentID: String, keyIndex: Int) -> URL {
        root
            .appendingPathComponent(instrumentID, isDirectory: true)
            .appendingPathComponent(String(format: "k%02d", keyIndex), isDirectory: true)
    }

    /// The saved take for a key, or nil if it has none. Newest by modification
    /// date in case more than one is there: the peak sits before the timestamp
    /// in the name, so names don't sort.
    static func latestClip(instrumentID: String, keyIndex: Int) -> URL? {
        let files = try? FileManager.default.contentsOfDirectory(
            at: directory(instrumentID: instrumentID, keyIndex: keyIndex),
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        return files?
            .filter { $0.pathExtension == "wav" }
            .max { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l < r
            }
    }
}

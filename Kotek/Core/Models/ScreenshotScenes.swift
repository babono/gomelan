//
//  ScreenshotScenes.swift
//  Kotek
//
//  App Store screenshots, DEBUG only. Launch with `-screenshot <scene>` to open
//  straight onto a screen with plausible data behind it — a fresh simulator has
//  no instruments and no finished session, so the picker and the results screen
//  would otherwise be an empty state and nothing at all.
//
//  Nothing here is saved: the profiles and the result live in memory for the
//  one launch. Pair it with `-hasSeenOnboarding YES -hasSeenGuide YES` so the
//  first-run panels stay down (launch arguments land in UserDefaults' argument
//  domain, which `Defaults` reads like any other).
//
//  The camera screens are not here. The simulator has no camera, and a practice
//  screen with a stock photo behind the overlay would be a picture of something
//  the app does not do — those are captured on a phone, over a real gangsa.
//

#if DEBUG
import Foundation

extension AppState {
    func applyScreenshotScene() {
        guard let scene = UserDefaults.standard.string(forKey: "screenshot") else { return }

        let base = profile
        func gangsa(_ name: String, notes: Int, sessions: Int, daysAgo: Double,
                    voiced: Bool = true) -> InstrumentProfile {
            var p = base
            // Any non-empty baseline reads as "voice learned" on the card.
            if voiced { p.strikeBaseline = [Float](repeating: 0.1, count: 120) }
            p.id = UUID().uuidString
            p.name = name
            p.accurateNotes = notes
            p.sessionCount = sessions
            p.lastUsedAt = ISO8601DateFormatter().string(from: .now.addingTimeInterval(-daysAgo * 86_400))
            return p
        }
        savedProfiles = [
            gangsa("Pemade at the sanggar", notes: 7_420, sessions: 38, daysAgo: 0.15),
            gangsa("Kantilan at home", notes: 1_860, sessions: 11, daysAgo: 2),
            gangsa("Banjar Kaja gangsa", notes: 240, sessions: 2, daysAgo: 9, voiced: false),
        ]
        profile = savedProfiles[0]
        selectedKotekan = kotekans.first

        switch scene {
        case "instruments":
            screen = .chooseInstrument
        case "kotekan":
            screen = .chooseKotekan
        case "guide":
            screen = .chooseKotekan
            visibleGuide = .kotekan
        case "results":
            lastResult = Self.sampleResult(kotekan: kotekans[0], half: chosenHalf,
                                           tempo: tempoScale, landed: 260)
            previousRecord = 0.74
            lastSetRecord = true
            previousNotesLanded = profile.notesLanded - 260
            screen = .results
        default:
            break
        }
    }

    /// Twelve passes of a half that starts shaky and settles — the shape a real
    /// session has, so the cycle chart has something to say.
    private static func sampleResult(kotekan: Kotekan, half: KotekanHalf,
                                     tempo: Double, landed: Int) -> SongResult {
        let slots = half == .polos ? kotekan.polos : kotekan.sangsih
        let keys = slots.compactMap { $0 }
        var rng = SeededRNG()  // the same session every capture
        var judgements: [NoteJudgement] = []
        var cycles: [CycleScore] = []
        for c in 0..<12 {
            let skill = min(0.97, 0.62 + Double(c) * 0.04)
            var score = 0, onBeat = 0, mistakes = 0
            for k in keys {
                let roll = Double.random(in: 0...1, using: &rng)
                let result: JudgementResult = roll < skill * 0.8 ? .perfect
                    : roll < skill ? .good
                    : roll < skill + 0.08 ? .lateEarly
                    : .miss
                let err = result == .miss ? 0 : Double.random(in: -60...60, using: &rng)
                judgements.append(NoteJudgement(keyIndex: k, result: result, timingErrorMs: err))
                score += result.score
                if result.onBeat { onBeat += 1 }
                if !result.isHit { mistakes += 1 }
            }
            cycles.append(CycleScore(index: c, startMs: Double(c * kotekan.slotsPerCycle * kotekan.strokeMs),
                                     noteCount: keys.count, score: score,
                                     onBeat: onBeat, mistakes: mistakes))
        }
        return SongResult(songTitle: kotekan.name,
                          subtitle: "\(kotekan.name) · \(half.title) · \(Theme.tempoLabel(tempo))",
                          judgements: judgements, cycles: cycles, landedNotes: landed)
    }
}
/// SplitMix64. `SystemRandomNumberGenerator` cannot be seeded, and a result
/// that changes on every launch makes a screenshot impossible to retake.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64 = 0x6B6F74656B  // "kotek"
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
#endif

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
            func gangsa(
                _ name: String,
                notes: Int,
                sessions: Int,
                daysAgo: Double,
                voiced: Bool = true
            ) -> InstrumentProfile {
                var p = base
                // Any non-empty baseline reads as "voice learned" on the card.
                if voiced { p.strikeBaseline = [Float](repeating: 0.1, count: 120) }
                p.id = UUID().uuidString
                p.name = name
                p.accurateNotes = notes
                p.sessionCount = sessions
                p.lastUsedAt = ISO8601DateFormatter().string(from: .now.addingTimeInterval(-daysAgo * 86400))
                return p
            }
            savedProfiles = [
                gangsa("Pemade at the sanggar", notes: 7420, sessions: 38, daysAgo: 0.15),
                gangsa("Kantilan at home", notes: 1860, sessions: 11, daysAgo: 2),
                gangsa("Banjar Kaja gangsa", notes: 240, sessions: 2, daysAgo: 9, voiced: false)
            ]
            profile = savedProfiles[0]
            selectedKotekan = kotekans.first

            switch scene {
            case "instruments":
                screen = .chooseInstrument
            case "kotekan":
                screen = .chooseKotekan
            case "create":
                screen = .createKotek
            case "create-polos", "create-polos-roll":
                // Ngecog's polos alone: four beats, so one whole gong cycle
                // under one half. `-roll` opens the editor, not the gangsa.
                var k = kotekans.first { $0.id == "ngecog" } ?? kotekans[0]
                k.sangsih = k.sangsih.map { _ in nil }
                editingKotekan = k
                screen = .createKotek
            case "waterfall":
                renderHalves()
                screen = .waterfall
            case "coop", "coopSetup":
                // Babaru: the most unisons of the bundled figures (§6.6.4), so
                // the bands joining the lanes are on screen in every shot.
                selectedKotekan = kotekans.first { $0.id == "babaru" } ?? kotekans[0]
                coop = CoopSetup(playerName: "Wayan", instrumentID: savedProfiles[0].id)
                coop?.right.name = "Komang"
                screen = scene == "coop" ? .coopPlay : .coopSetup
            case "learn":
                startLearn(kotekans[0], fromStart: true)
            case "learn-step", "learn-buildup":
                // Straight to a waterfall step, past Watch and Listen.
                startLearn(kotekans[0], fromStart: true)
                advanceLearn()
                advanceLearn()
                if scene == "learn-buildup" { advanceLearn() }
            case "guide":
                screen = .chooseKotekan
                visibleGuide = .kotekan
            case "results":
                lastResult = Self.sampleResult(
                    kotekan: kotekans[0],
                    half: chosenHalf,
                    tempo: tempoScale,
                    landed: 260
                )
                previousRecord = 0.74
                lastSetRecord = true
                screen = .results
            default:
                break
            }
        }

        /// The results screen over a made-up session of Babaru, from Settings → Debug.
        ///
        /// Babaru because it is the longest bundled figure (32 slots, past the
        /// graph's 16-slot window), so the minimap and scrolling are on screen.
        ///
        /// ponytail: leaves Babaru as `selectedKotekan`, so Retry from here plays it.
        func openMockResults() {
            let babaru = kotekans.first { $0.id == "babaru" } ?? kotekans[0]
            selectedKotekan = babaru
            lastResult = Self.sampleResult(kotekan: babaru, half: chosenHalf, tempo: tempoScale, landed: 260)
            lastResultIsSample = true
            previousRecord = 0.74
            lastSetRecord = true
            screen = .results
        }

        /// Twelve passes of a half that starts shaky and settles, and keeps
        /// slipping in its third quarter — the shape a real session has, so the
        /// cycle chart and the overview have something to say.
        private static func sampleResult(
            kotekan: Kotekan,
            half: KotekanHalf,
            tempo: Double,
            landed: Int
        ) -> SongResult {
            let song = kotekan.makeSong(half: half, cycles: 1)
            var rng = SeededRNG() // the same session every capture
            var judgements: [NoteJudgement] = []
            var cycles: [CycleScore] = []
            for c in 0 ..< 12 {
                let settled = min(0.97, 0.62 + Double(c) * 0.04)
                var score = 0, onBeat = 0, mistakes = 0
                for (i, note) in song.notes.enumerated() {
                    let third = note.timeMs * 4 / song.durationMs == 2
                    let skill = third ? settled - 0.22 : settled
                    let roll = Double.random(in: 0 ... 1, using: &rng)
                    let result: JudgementResult = roll < skill * 0.8 ? .perfect
                        : roll < skill ? .good
                        : roll < skill + 0.08 ? .lateEarly
                        : .miss
                    let err = result == .miss ? 0 : Double.random(in: -60 ... 60, using: &rng)
                    judgements.append(NoteJudgement(
                        keyIndex: note.keyIndex,
                        stroke: i,
                        result: result,
                        timingErrorMs: err
                    ))
                    score += result.score
                    if result.onBeat { onBeat += 1 }
                    if !result.isHit { mistakes += 1 }
                }
                cycles.append(CycleScore(
                    index: c,
                    startMs: Double(c * kotekan.slotsPerCycle * kotekan.strokeMs),
                    noteCount: song.notes.count,
                    score: score,
                    onBeat: onBeat,
                    mistakes: mistakes
                ))
            }
            // A few passes of the other side too, with a wrong-bilah habit, so the
            // graph shows marks on both halves of the interlock.
            var partner: [NoteJudgement] = []
            let other = kotekan.makeSong(half: half.other, cycles: 1)
            for _ in 0 ..< 4 {
                for (i, note) in other.notes.enumerated() {
                    let roll = Double.random(in: 0 ... 1, using: &rng)
                    let result: JudgementResult = roll < 0.12 ? .wrongKey : .perfect
                    partner.append(NoteJudgement(keyIndex: note.keyIndex, stroke: i, result: result, timingErrorMs: 0))
                }
            }
            return SongResult(
                songTitle: kotekan.name,
                subtitle: "\(kotekan.name) · \(half.title) · \(Theme.tempoLabel(tempo))",
                judgements: judgements,
                partnerJudgements: partner,
                cycles: cycles,
                strokes: song.notes,
                cycleMs: song.durationMs,
                landedNotes: landed,
                // Twelve passes at the figure's own speed.
                practiceSeconds: Double(song.durationMs) * 12 / tempo / 1000
            )
        }
    }

    /// SplitMix64. `SystemRandomNumberGenerator` cannot be seeded, and a result
    /// that changes on every launch makes a screenshot impossible to retake.
    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64 = 0x6B_6F74_656B // "kotek"
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
#endif

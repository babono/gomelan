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
                var rng = SeededRNG() // the same session every capture
                lastResult = Self.sampleResult(
                    kotekan: kotekans[0],
                    half: chosenHalf,
                    tempo: tempoScale,
                    landed: 260,
                    rng: &rng
                )
                previousRecord = 0.74
                lastSetRecord = true
                screen = .results
            case "setup-1":
                // Adding a gangsa, from its first step.
                addNewInstrument()
            case "setup-2":
                addNewInstrument()
                openNoteCapture(setup: true)
            case "setup-3":
                addNewInstrument()
                openControllerSetup(returnTo: .chooseKotekan, offer: true)
            case "instruments-empty":
                // The first-run picker: no gangsa yet.
                savedProfiles = []
                screen = .chooseInstrument
            default:
                // Any other screen by its route name (`-screenshot settings`),
                // with the sample gangsa above behind it — for checking a
                // screen's look without tapping through to it.
                if let route = Route(rawValue: scene) { screen = route }
            }
        }

        /// The results screen over a made-up session of Babaru, from Settings → Debug.
        ///
        /// A new session every time, and the real overview run on it: a canned
        /// one could not show whether the model reads the numbers right.
        ///
        /// ponytail: leaves Babaru as `selectedKotekan`, so Retry from here plays it.
        func openMockResults() {
            PolishSpot.selfCheck()
            let babaru = kotekans.first { $0.id == "babaru" } ?? kotekans[0]
            selectedKotekan = babaru
            var rng = SystemRandomNumberGenerator()
            lastResult = Self.sampleResult(kotekan: babaru, half: chosenHalf, tempo: tempoScale, landed: 260, rng: &rng)
            previousRecord = 0.74
            lastSetRecord = true
            screen = .results
        }

        /// A session that starts shaky and settles, with one weak quarter of
        /// the cycle and a few habits for "Where to polish" — a stroke that
        /// drags, one that rushes, one that lands a bar off — each on a stroke,
        /// and at a rate, the generator picks. Seeded for screenshots, so a
        /// capture can be retaken; random from Debug.
        private static func sampleResult(
            kotekan: Kotekan,
            half: KotekanHalf,
            tempo: Double,
            landed: Int,
            rng: inout some RandomNumberGenerator
        ) -> SongResult {
            let song = kotekan.makeSong(half: half, cycles: 1)
            let count = song.notes.count
            let passes = Int.random(in: 4 ... 14, using: &rng)
            let start = Double.random(in: 0.45 ... 0.85, using: &rng)
            let weakQuarter = Int.random(in: 0 ..< 4, using: &rng)
            let habits = Array((0 ..< count).shuffled(using: &rng).prefix(3))
            let rates = (0 ..< 3).map { _ in Double.random(in: 0.2 ... 0.8, using: &rng) }
            var judgements: [NoteJudgement] = []
            var cycles: [CycleScore] = []
            for c in 0 ..< passes {
                let settled = min(0.97, start + Double(c) * 0.04)
                var score = 0, onBeat = 0, mistakes = 0
                for (i, note) in song.notes.enumerated() {
                    let weak = note.timeMs * 4 / song.durationMs == weakQuarter
                    let skill = weak ? settled - 0.22 : settled
                    let roll = Double.random(in: 0 ... 1, using: &rng)
                    var result: JudgementResult = roll < skill * 0.8 ? .perfect
                        : roll < skill ? .good
                        : roll < skill + 0.08 ? .lateEarly
                        : .miss
                    var err = result == .miss ? 0 : Double.random(in: -60 ... 60, using: &rng)
                    var struck = note.keyIndex
                    let habit = Double.random(in: 0 ... 1, using: &rng)
                    if i == habits.first, habit < rates[0] {
                        result = .lateEarly
                        err = -Double.random(in: 110 ... 170, using: &rng)
                    } else if habits.count > 1, i == habits[1], habit < rates[1] {
                        result = .lateEarly
                        err = Double.random(in: 110 ... 170, using: &rng)
                    } else if habits.count > 2, i == habits[2], habit < rates[2] {
                        result = .wrongKey
                        struck = note.keyIndex + (note.keyIndex > 0 && habit < rates[2] / 2 ? -1 : 1)
                    }
                    judgements.append(NoteJudgement(
                        keyIndex: struck,
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
                    noteCount: count,
                    score: score,
                    onBeat: onBeat,
                    mistakes: mistakes
                ))
            }
            return SongResult(
                songTitle: kotekan.name,
                subtitle: "\(kotekan.name) · \(half.title) · \(Theme.tempoLabel(tempo))",
                judgements: judgements,
                cycles: cycles,
                strokes: song.notes,
                cycleMs: song.durationMs,
                landedNotes: landed,
                // Every pass at the figure's own speed.
                practiceSeconds: Double(song.durationMs) * Double(passes) / tempo / 1000,
                passes: passes,
                topTempoScale: tempo
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

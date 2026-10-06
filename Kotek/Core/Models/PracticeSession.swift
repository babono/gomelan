//
//  PracticeSession.swift
//  Kotek
//
//  One finished practice session, in the app's terms.
//

import Foundation

nonisolated struct PracticeSession: Sendable {
    var kotekanID: String?
    var half: String
    var bpm: Int
    var tempoScale: Double
    var leniency: Double
    var cycleCount: Int
    var accuracy: Double?
    var onTimeCount: Int
    var wrongKeyCount: Int
    var missedCount: Int
    var landedNotes: Int
    var bestStreak: Int
    var driftMs: Double?

    init(
        kotekanID: String? = nil,
        half: String,
        bpm: Int,
        tempoScale: Double,
        leniency: Double,
        cycleCount: Int,
        accuracy: Double? = nil,
        onTimeCount: Int,
        wrongKeyCount: Int,
        missedCount: Int,
        landedNotes: Int,
        bestStreak: Int,
        driftMs: Double? = nil
    ) {
        self.kotekanID = kotekanID
        self.half = half
        self.bpm = bpm
        self.tempoScale = tempoScale
        self.leniency = leniency
        self.cycleCount = cycleCount
        self.accuracy = accuracy
        self.onTimeCount = onTimeCount
        self.wrongKeyCount = wrongKeyCount
        self.missedCount = missedCount
        self.landedNotes = landedNotes
        self.bestStreak = bestStreak
        self.driftMs = driftMs
    }
}

extension PracticeSession {
    init(
        result: SongResult,
        kotekan: Kotekan?,
        half: KotekanHalf,
        tempoScale: Double,
        leniency: Double
    ) {
        let judged = result.judgements.map(\.result)
        let hits = judged.filter { $0 != .miss && $0 != .wrongKey }
        var streak = 0, best = 0
        for r in judged {
            streak = r.onBeat ? streak + 1 : 0
            best = max(best, streak)
        }
        self.init(
            kotekanID: kotekan?.id,
            half: half.rawValue,
            //R The figure's own tempo, per grid slot — the same number the seed
            //R stores in `kotekan.bpm`. What was actually played is this times
            //R `tempoScale`, which is stored beside it rather than folded in.
            bpm: kotekan.map { Int((60000.0 / Double($0.strokeMs)).rounded()) } ?? 0,
            tempoScale: tempoScale,
            leniency: leniency,
            cycleCount: result.cycles.count,
            //R The headline number — the best window, as the results screen
            //R shows it — and NULL rather than 0 when no pass completed.
            accuracy: result.best?.accuracy,
            onTimeCount: judged.filter(\.onBeat).count,
            wrongKeyCount: judged.filter { $0 == .wrongKey }.count,
            missedCount: judged.filter { $0 == .miss }.count,
            landedNotes: result.landedNotes,
            bestStreak: best,
            driftMs: hits.isEmpty ? nil : result.driftMs
        )
    }
}

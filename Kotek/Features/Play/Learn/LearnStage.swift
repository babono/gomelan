//
//  LearnStage.swift
//  Kotek
//
//  Learn: a pattern taught in order, the first time it is picked. Watch both
//  halves together; then polos and then sangsih, each heard, played a note at
//  a time, and brought up to speed; then free play, the screen that was all
//  there was before.
//
//  Sangsih is taught over polos, which plays through all three of its steps:
//  sangsih alone is a scatter of offbeats, and it is the interlock that makes
//  sense of it.
//

import Foundation

enum LearnStage: Hashable {
    case watch
    /// Your half, played for you once at full speed.
    case listen(KotekanHalf)
    /// One note at a time: the figure stops on each until it is struck.
    case step(KotekanHalf)
    /// From half speed to a little over full, a step at a time.
    case buildUp(KotekanHalf)

    static let order: [LearnStage] = [
        .watch,
        .listen(.polos), .step(.polos), .buildUp(.polos),
        .listen(.sangsih), .step(.sangsih), .buildUp(.sangsih)
    ]

    var next: LearnStage? {
        guard let i = Self.order.firstIndex(of: self), i + 1 < Self.order.count else { return nil }
        return Self.order[i + 1]
    }

    var half: KotekanHalf? {
        switch self {
        case .watch: nil
        case let .listen(h), let .step(h), let .buildUp(h): h
        }
    }

    /// What this step asks of you, under the strip.
    var title: String {
        switch self {
        case .watch: String(localized: "Watch both halves")
        case .listen: String(localized: "Listen")
        case .step: String(localized: "Note by note")
        case .buildUp: String(localized: "Build up speed")
        }
    }

    /// The speeds Build up climbs, ending a little over the figure as written
    /// so full speed feels within reach afterwards.
    static let buildUpTempos: [Double] = [0.5, 0.75, 1.0, 1.1]
    /// What each of those is called on the stepper (`BuildUpStepper`).
    static let buildUpNames: [LocalizedStringResource] = [
        "Slow",
        "Steady",
        "Full speed",
        LocalizedStringResource("BuildUp.faster", defaultValue: "Faster")
    ]
    /// Without sensors nothing says whether a pass was clean, so each speed
    /// gets a set number of passes instead.
    static let passesPerTempoUnsensed = 2
    /// With them, one pass at this accuracy moves you up.
    static let accuracyToSpeedUp = 0.8
}

/// What Learn remembers, per pattern, on this device. Which half you reached
/// (so leaving halfway does not repeat a half you finished), and whether it
/// is done (so the pattern opens straight into free play from then on).
enum LearnProgress {
    private static func key(_ id: String) -> String {
        "learn.\(id)"
    }

    static func isDone(_ id: String) -> Bool {
        Defaults.string(key(id)) == "done"
    }

    /// Where to pick up: sangsih if polos was finished, else the start.
    static func resumeStage(_ id: String) -> LearnStage {
        Defaults.string(key(id)) == "sangsih" ? .listen(.sangsih) : .watch
    }

    static func reachedSangsih(_ id: String) {
        guard !isDone(id) else { return }
        UserDefaults.standard.set("sangsih", forKey: key(id))
    }

    static func finished(_ id: String) {
        UserDefaults.standard.set("done", forKey: key(id))
        UserDefaults.standard.set(true, forKey: "learnedAny")
    }

    /// Once one pattern has been learned, Learn can be skipped on the others.
    static var learnedAny: Bool {
        Defaults.bool("learnedAny", false)
    }
}

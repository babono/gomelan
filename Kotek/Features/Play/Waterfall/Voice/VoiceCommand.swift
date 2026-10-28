//
//  VoiceCommand.swift
//  Kotek
//
//  What the waterfall answers to while both hands are on the panggul. A short
//  fixed list matched against the transcript, not free speech: the room is a
//  ringing gangsa, and every extra phrase is one more thing it can be misheard
//  as.
//

import Foundation

enum VoiceCommand: Equatable {
    case slower
    case faster
    case normalSpeed
    case half(KotekanHalf)
    case switchHalf
    case pause
    case resume
    case end
    case restart
    case next

    /// Longest phrases first, so "speed up" is not read as something shorter
    /// inside it. Sangsih is spelled the ways English dictation hears it.
    private static let phrases: [(String, VoiceCommand)] = [
        ("normal speed", .normalSpeed),
        ("slow down", .slower),
        ("speed up", .faster),
        ("start over", .restart),
        ("from the top", .restart),
        ("other side", .switchHalf),
        ("sang sih", .half(.sangsih)),
        ("song see", .half(.sangsih)),
        ("sung see", .half(.sangsih)),
        ("go on", .resume),
        ("slower", .slower),
        ("faster", .faster),
        ("polos", .half(.polos)),
        ("sangsih", .half(.sangsih)),
        ("sangsi", .half(.sangsih)),
        ("switch", .switchHalf),
        ("swap", .switchHalf),
        ("pause", .pause),
        ("stop", .pause),
        ("wait", .pause),
        ("resume", .resume),
        ("continue", .resume),
        ("restart", .restart),
        ("again", .restart),
        ("quit", .end),
        ("finish", .end),
        ("end", .end),
        ("next", .next),
        ("skip", .next),
    ]

    /// Fed to the recogniser so these win over their sound-alikes.
    static let vocabulary = phrases.map(\.0) + ["Polos", "Sangsih"]

    /// The LAST command in `text`, by whole words — "end" in "friend" is not
    /// one. Last, because a result is the whole utterance so far: "polos…
    /// pause" said in one breath arrives as "polos", then "polos pause", and
    /// the new word is the one to act on.
    init?(heard text: String) {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        let padded = " " + words.joined(separator: " ") + " "
        var best: (end: String.Index, command: VoiceCommand)?
        for (phrase, command) in Self.phrases {
            guard let r = padded.range(of: " \(phrase) ", options: .backwards) else { continue }
            // Strictly later only: on a tie the longer phrase, listed first, stands.
            if best == nil || r.upperBound > best!.end { best = (r.upperBound, command) }
        }
        guard let best else { return nil }
        self = best.command
    }

    /// How the caption names it.
    var title: String {
        switch self {
        case .slower: "Slower"
        case .faster: "Faster"
        case .normalSpeed: "Normal speed"
        case let .half(half): half.title
        case .switchHalf: "Switch"
        case .pause: "Pause"
        case .resume: "Resume"
        case .end: "End"
        case .restart: "Restart"
        case .next: "Next"
        }
    }
}

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

    /// The language the commands are heard in: the app's own, when the
    /// device can transcribe it, else English.
    enum Language: Equatable {
        case english, indonesian

        var locale: Locale {
            Locale(identifier: self == .indonesian ? "id-ID" : "en-US")
        }

        /// What the screen is in, not the phone's region — the words to say
        /// should be the words the player is reading.
        static var preferred: Language {
            Bundle.main.preferredLocalizations.first == "id" ? .indonesian : .english
        }
    }

    private static func phrases(_ language: Language) -> [(String, VoiceCommand)] {
        language == .indonesian ? indonesian : english
    }

    /// Longest phrases first, so "speed up" is not read as something shorter
    /// inside it. Sangsih is spelled the ways English dictation hears it.
    private static let english: [(String, VoiceCommand)] = [
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
        ("skip", .next)
    ]

    /// The same commands as a teacher would call them in Indonesian. Kept to
    /// words that rarely turn up mid-sentence otherwise — "sudah" was left out
    /// for that reason. Longest first, as above.
    private static let indonesian: [(String, VoiceCommand)] = [
        ("kecepatan normal", .normalSpeed),
        ("tempo normal", .normalSpeed),
        ("lebih pelan", .slower),
        ("lebih cepat", .faster),
        ("dari awal", .restart),
        ("mulai lagi", .restart),
        ("tukar bagian", .switchHalf),
        ("ganti bagian", .switchHalf),
        ("sang sih", .half(.sangsih)),
        ("pelankan", .slower),
        ("pelan", .slower),
        ("lambat", .slower),
        ("percepat", .faster),
        ("cepat", .faster),
        ("normal", .normalSpeed),
        ("polos", .half(.polos)),
        ("sangsih", .half(.sangsih)),
        ("sangsi", .half(.sangsih)),
        ("tukar", .switchHalf),
        ("ganti", .switchHalf),
        ("jeda", .pause),
        ("berhenti", .pause),
        ("tunggu", .pause),
        ("stop", .pause),
        ("lanjutkan", .resume),
        ("lanjut", .resume),
        ("terus", .resume),
        ("ulangi", .restart),
        ("ulang", .restart),
        ("selesai", .end),
        ("keluar", .end),
        ("berikutnya", .next),
        ("lewati", .next),
        ("skip", .next)
    ]

    /// Fed to the recogniser so these win over their sound-alikes.
    static func vocabulary(_ language: Language) -> [String] {
        phrases(language).map(\.0) + ["Polos", "Sangsih"]
    }

    /// The LAST command in `text`, by whole words — "end" in "friend" is not
    /// one. Last, because a result is the whole utterance so far: "polos…
    /// pause" said in one breath arrives as "polos", then "polos pause", and
    /// the new word is the one to act on.
    init?(heard text: String, in language: Language) {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        let padded = " " + words.joined(separator: " ") + " "
        var best: (end: String.Index, command: VoiceCommand)?
        for (phrase, command) in Self.phrases(language) {
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
        case .slower: String(localized: "Slower")
        case .faster: String(localized: "Faster")
        case .normalSpeed: String(localized: "Normal speed")
        case let .half(half): half.title
        case .switchHalf: String(localized: "Switch")
        case .pause: String(localized: "Pause")
        case .resume: String(localized: "Resume")
        case .end: String(localized: "End")
        case .restart: String(localized: "Restart")
        // Its own key: the Next button is "Lanjut" in Indonesian, and spoken
        // "lanjut" means resume here — the caption must name the word to say.
        case .next: String(localized: "VoiceCommand.next", defaultValue: "Next")
        }
    }
}

//
//  Kotekan.swift
//  Kotek
//
//  Kotekan are the interlocking figures at the heart of Balinese gangsa playing.
//  Two players share one composite melody: POLOS lands on the beat, SANGSIH
//  answers off the beat, and the two halves woven together make the line you
//  hear. This app teaches one half at a time.
//
//  A kotekan is stored as two 16-slot grids (`polos` / `sangsih`) over one gong
//  cycle. Each slot holds a KEY INDEX to strike, or nil for a rest — indices,
//  never pitches, so the same figure is portable across differently tuned
//  instruments (PRD §7). `makeSong` renders the chosen half over N cycles into
//  the note sequence the PlayEngine already knows how to run.
//
//  The same two grids also carry the exhibition MELODIES — Javanese lagu
//  dolanan with both halves identical, so one person alone plays the whole tune.
//  Nothing downstream needed changing for that: a melody is a kotekan whose
//  halves happen to agree. See `KotekanKind` and `melodies`.
//

import Foundation

enum KotekanHalf: String, Equatable, Identifiable {
    case polos
    case sangsih

    var id: String { rawValue }
    var title: String { self == .polos ? "Polos" : "Sangsih" }
    /// The half your partner plays — the one the app takes over when you play alone.
    var other: KotekanHalf { self == .polos ? .sangsih : .polos }
    var eyebrow: String { self == .polos ? "On the beat" : "Off the beat" }
    var blurb: String {
        self == .polos
            ? "The straight half. You land on the pulse and hold the frame steady."
            : "The answering half. You fill the gaps polos leaves — harder, more fun."
    }
}

/// What a catalogue entry IS, which is the one thing the two kinds of entry do
/// not share.
///
/// A `figure` is the teaching material: two halves that only make sense woven
/// together, learned one half at a time. A `melody` is a whole tune carried by
/// both halves in unison — added for exhibition tables, where the person sitting
/// down has never held a panggul and will be there for four minutes. Interlocking
/// needs a partner, a shared pulse and a reason to care about the off-beat; a
/// dolanan everybody in the room already knows needs none of those, so it is
/// something a stranger can actually finish.
///
/// It exists to keep `level` off the melody cards. A folk tune has no level in
/// the kotekan ladder, and printing "Level 1" on one claims it is the easy end
/// of a progression it is not part of.
enum KotekanKind: Equatable {
    case figure
    case melody
}

struct Kotekan: Identifiable, Equatable {
    var id: String
    var name: String            // "Kotekan Telu"
    var level: Int              // 1…3 — figures only; a melody has no rung
    var kind: KotekanKind = .figure
    var toneLabel: String       // "3 tones", "4 tones", "Neighbour", "Sparse"
    var blurb: String           // one-line description for the selection card
    /// One gong cycle laid out as 16 grid slots. A value is the key index to
    /// strike on that slot; nil is a rest.
    var polos: [Int?]
    var sangsih: [Int?]
    /// Milliseconds per grid slot — sets the tempo (smaller = faster).
    var strokeMs: Int

//    static let strokesPerCycle = 16
    var slotsPerCycle: Int { polos.count }

    /// Highest key index touched by either half, so we know the smallest
    /// instrument this figure fits on.
    var requiredKeys: Int {
        let maxIndex = (polos + sangsih).compactMap { $0 }.max() ?? 0
        return maxIndex + 1
    }

    func pattern(_ half: KotekanHalf) -> [Int?] {
        half == .polos ? polos : sangsih
    }

    /// The bilah this figure touches across BOTH halves — the lanes the river
    /// draws. Taken from the figure rather than from what is on screen, so the
    /// lanes stay put as the notes go by.
    var voicedKeyRange: ClosedRange<Int> {
        let used = (polos + sangsih).compactMap { $0 }
        guard let low = used.min(), let high = used.max() else { return 0...0 }
        return low...high
    }

    /// How many actual strokes a half plays in one cycle (rests excluded).
    func strokeCount(_ half: KotekanHalf) -> Int {
        pattern(half).compactMap { $0 }.count
    }

    var cycleMs: Int { slotsPerCycle * strokeMs }

    /// The eyebrow above the name on a picker card.
    ///
    /// Figures carry their rung, because the four of them ARE a progression and
    /// the number is the reason to swipe right. Melodies carry only what they
    /// are — they sit in the same rail but not on the same ladder.
    var catalogLabel: String {
        kind == .figure ? "Level \(level) · \(toneLabel)" : toneLabel
    }

    /// Render the chosen half, repeated `cycles` times, into engine notes.
    func makeSong(half: KotekanHalf, cycles: Int) -> Song {
        let grid = pattern(half)
        var notes: [Note] = []
        for c in 0..<cycles {
            for (slot, value) in grid.enumerated() {
                guard let key = value else { continue }
                let t = (c * slotsPerCycle + slot) * strokeMs
                notes.append(Note(keyIndex: key, timeMs: t, durationMs: Int(Double(strokeMs) * 0.9)))
            }
        }
        let duration = cycles * cycleMs
        // One "beat" per grid slot — keeps the metronome aligned to the pulse.
        let bpm = max(1, Int((60000.0 / Double(strokeMs)).rounded()))
        return Song(id: "\(id)-\(half.rawValue)",
                    title: name,
                    difficulty: .beginner,
                    bpm: bpm,
                    requiredKeys: requiredKeys,
                    durationMs: duration,
                    notes: notes)
    }
}

// MARK: - Bundled figures

extension Kotekan {
    /// A tune both halves play together.
    ///
    /// One grid in, the same grid out on both sides. Writing the array twice was
    /// the obvious thing and it is wrong twice over: sixty-four slots typed out
    /// again is sixty-four chances for the halves to differ by one note, and a
    /// melody whose halves have silently drifted apart is a bug that only ever
    /// shows up as a stranger at an exhibition table being marked wrong.
    ///
    /// The unison is also why the river reads these as it does — `NotesRiver`
    /// splits a slot both halves share into a polos/sangsih pair, so every note
    /// of a melody is drawn two-tone. That is accurate: everyone is on it.
    static func melody(id: String,
                       name: String,
                       toneLabel: String,
                       blurb: String,
                       grid: [Int?],
                       strokeMs: Int) -> Kotekan {
        Kotekan(id: id, name: name, level: 0, kind: .melody,
                toneLabel: toneLabel, blurb: blurb,
                polos: grid, sangsih: grid, strokeMs: strokeMs)
    }

    /// Everything the picker offers: the figures first, then the melodies.
    ///
    /// Order is the rail order, and the figures come first deliberately. This is
    /// a kotekan app and the ladder is the point; the dolanan are the thing you
    /// swipe PAST the teaching material to reach, not the front door.
    static let bundled: [Kotekan] = figures + melodies

    /// The four figures, easiest first.
    /// Each figure keeps its source pattern exactly as notated in the reference
    /// videos; Babaru uses a 32-slot cycle while the other figures use 8 or 16.
    static let figures: [Kotekan] = [
        Kotekan(
            id: "ubitannyendok",
            name: "Ubitan Nyendok",
            level: 1,
            toneLabel: "Telu family",
            blurb: "A short, repeating telu-family motif that introduces the basic interlocking movement.",
            polos:   [7, nil, 6, 7, nil, 7, 6, nil],
            sangsih: [nil, 5, 6, nil, 5, nil, 6, 5],
            strokeMs: 250
        ),
        Kotekan(
            id: "kabelet",
            name: "Kabelet",
            level: 2,
            toneLabel: "Telu family",
            blurb: "A foundational telu-family kotekan built around a shared middle-note anchor.",
            polos:   [4, nil, 5, 4, nil, 4, 5, nil],
            sangsih: [7, 6, nil, 7, 6, 7, nil, 6],
            strokeMs: 250
        ),
        Kotekan(
            id: "ngecog",
            name: "Ngecog",
            level: 3,
            toneLabel: "Empat · Leap",
            blurb: "An empat-family pattern defined by wide leaps between 1, 3, 5, and 6, without a shared anchor.",
            polos:   [4, nil, 3, 4, nil, 4, 3, nil, 4, nil, 2, nil, 4, nil, 2, nil],
            sangsih: [nil, 2, 3, nil, 2, nil, 3, 2, nil, 1, nil, 3, nil, 1, nil, 3],
            strokeMs: 250
        ),
        Kotekan(
            id: "babaru",
            name: "Babaru",
            level: 4,
            toneLabel: "Capstone",
            blurb: "The capstone figure: a longer phrase with a wider pitch range and greater memory and hand-span demands.",
            polos:   [6, nil, 7, nil, 6, 7, nil, 6, 7, nil, 8, nil, 7, 8, nil, 7, 8, nil, 7, nil, 8, 7, nil, 8, 7, nil, 6, nil, 7, 6, nil, 7],
            sangsih: [nil, 6, nil, 5, 6, nil, 5, 6, nil, 7, nil, 6, 7, nil, 6, 7, nil, 8, nil, 9, 8, nil, 9, 8, nil, 7, nil, 8, 7, nil, 8, 7],
            strokeMs: 250
        ),
    ]

    /// "Gundul gundul pacul cul, gembelengan" — 32 slots, one gong cycle.
    ///
    /// Sung twice, the second time as "Nyunggi nyunggi wakul kul": different
    /// words, same notes, so it is the same array twice rather than two arrays.
    private static let gundulVerse: [Int?] = [
        // "Gundul gundul pacul cul"   1  3  1  3  4  5  5   ·
        //  on the bilah:               4  5  4  5  6  7  7
        3, nil, 4, nil, 3, nil, 4, nil, 5, nil, 6, nil, 6, nil, nil, nil,
        // "gembelengan"               7  1' 7  1' 7  5   ·   ·
        //  on the bilah:               8  9  8  9  8  7
        7, nil, 8, nil, 7, nil, 8, nil, 7, nil, 6, nil, nil, nil, nil, nil,
    ]

    /// "Wakul ngglimpang segane dadi sak latar" — 32 slots, and also sung twice.
    private static let gundulWakul: [Int?] = [
        // "Wakul ngglimpang segane"   1  3  5  4  4  5  4  3
        //  on the bilah:               4  5  7  6  6  7  6  5
        3, nil, 4, nil, 6, nil, 5, nil, 5, nil, 6, nil, 5, nil, 4, nil,
        // "dadi sak latar"            1  4  3  1   ·   ·   ·   ·
        //  on the bilah:               4  6  5  4
        //
        //  Four beats of rest before the next phrase. That tail is a breath, not
        //  a gap to be trimmed: cut it and the second time round lands on top of
        //  the last note of the first.
        3, nil, 5, nil, 4, nil, 3, nil, nil, nil, nil, nil, nil, nil, nil, nil,
    ]

    /// Two Javanese *lagu dolanan* laid out for the gangsa, for exhibition
    /// tables. Both halves play them in unison — see `melody`.
    ///
    /// WHY THESE ARE NOT KOTEKAN, and why that is fine. A figure is half a line
    /// and sounds like half a line until somebody plays the other half; a
    /// visitor with four minutes and no partner gets a rhythm exercise out of
    /// it. A tune the whole room can already hum is finishable by one person on
    /// one pass, and the app still does its real job around it — the camera
    /// still says which bilah, the mic still says when.
    ///
    /// FITTING A JAVANESE TUNE ONTO A BALINESE GANGSA. Selisir has five tones to
    /// the octave, so a melody has to be pentatonic before it can be played at
    /// all — the five tones of the tune, in ascending order, land on five
    /// neighbouring bilah, and the sixth bilah up is the octave of the first.
    /// The contour survives that exactly; the intervals do not survive it
    /// exactly, and cannot, because pelog is not the diatonic scale these tunes
    /// get printed in. It lands closer than you would expect — see the octave
    /// note on each tune.
    ///
    /// WHICH SIX BILAH, and how that was got wrong once. Both tunes were first
    /// placed by arithmetic: take the cents in the bundled profile, find the
    /// rotation of selisir whose steps best match the tune's, start there. It
    /// put Gundul-Gundul Pacul two keys too low, because the bundled profile is
    /// a PLACEHOLDER — `ResourceLoader.embeddedProfileJSON` says so — and a real
    /// gangsa is not obliged to agree with it. Every village tunes differently;
    /// that is the premise of the whole app, and it applies to this file too.
    ///
    /// So the numbers below are the bilah people actually strike, taken from
    /// playing the tunes on the instrument, and they are not derived from
    /// anything. Both live inside bilah 4…9 as the overlay labels them, which is
    /// the other reason to place them where they are placed: a table running
    /// both tunes back to back never asks anyone to move their hands.
    static let melodies: [Kotekan] = [
        //  Not angka: 1 3 1 3 4 5 5 / 7 1' 7 1' 7 5 / 1 3 5 4 4 5 4 3 1 4 3 1.
        //  Five tones — 1 3 4 5 7 — so it is already pentatonic and nothing has
        //  to be thrown away.
        //
        //  do = bilah index 3, which is bilah 4 on the overlay: the tune opens
        //  4 5 4 5 6 7 7 / 8 9 8 9 8 7 on the instrument, and the five tones run
        //  up five neighbouring keys from there, so 1' lands on bilah 9 exactly
        //  an octave above the 4 it started on.
        //
        //  128 slots, because the song is A A B B and playing it A B A B is a
        //  different song. Both halves are sung twice: the verse comes round
        //  with "Nyunggi nyunggi wakul kul" the second time and the closing line
        //  simply repeats, and in both cases the NOTES are identical — which is
        //  why one array serves for each and the form is spelled out below
        //  rather than typed twice.
        //
        //  The colotomic cycle is 32 beats, so a length that is a multiple of 32
        //  keeps the gong on the turn of the phrase forever; everything else
        //  walks. 128 is four gong cycles, one per half-phrase. Notes fall on
        //  even slots — one every 500 ms at the bundled tempo, which is a
        //  quarter note and a pace a stranger can follow.
        //
        //  A full pass is 32 seconds. That is long next to a kotekan, and it is
        //  the song: nothing shorter is Gundul-Gundul Pacul. It does mean eight
        //  passes — `SongResult.scoringWindow`, what a record costs — is four
        //  minutes at this table rather than one.
        melody(
            id: "gundulpacul",
            name: "Gundul-Gundul Pacul",
            toneLabel: "Lagu dolanan · Unison",
            blurb: "The Javanese children's song, both halves together — for anyone sitting down at the gangsa for the first time.",
            grid: gundulVerse + gundulVerse + gundulWakul + gundulWakul,
            strokeMs: 250
        ),

        //  NOT THE LANCARAN. This was first taken from the balungan of Lancaran
        //  Suwe Ora Jamu — pelog nem, one note per two syllables — on the
        //  reasoning that a gamelan app should play what a gamelan plays. It
        //  came out unrecognisable, and the reason is worth keeping: a balungan
        //  is a SKELETON, the frame a gamelan elaborates around, and nobody
        //  hums it. The tune below is the sung melody, one note per syllable,
        //  as it is played on the gangsa.
        //
        //  Bilah 5 7 7 5 6 7 / 5 6 6 7 5 6 / 7 8 8 9 9 8 8 / 7 7 6 6 5 6 9 —
        //  twenty-six notes, four lyric lines of 6 · 6 · 7 · 7.
        //
        //  64 slots, two gong cycles. Notes land on even slots — every 500 ms,
        //  the same stroke pace as Gundul-Gundul Pacul, so a table running both
        //  does not change gear between them — and each line closes with a beat
        //  or two of breath, EXCEPT the third, which runs straight into the
        //  fourth. The lines are therefore 16 · 16 · 14 · 18 rather than four
        //  even sixteens, and the second gong still lands exactly on "Suwe ora
        //  ketemu".
        melody(
            id: "suweorajamu",
            name: "Suwe Ora Jamu",
            toneLabel: "Lagu dolanan · Unison",
            blurb: "The one everyone in the room can already hum, carried by both halves at once.",
            grid: [
                // "Suwe ora jamu"           bilah 5  7  7  5  6  7
                4, nil, 6, nil, 6, nil, 4, nil, 5, nil, 6, nil, nil, nil, nil, nil,
                // "jamu godhong telo"       bilah 5  6  6  7  5  6
                4, nil, 5, nil, 5, nil, 6, nil, 4, nil, 5, nil, nil, nil, nil, nil,
                // "Suwe ora ketemu"         bilah 7  8  8  9  9  8  8
                //
                //  NO BREATH AT THE END OF THIS ONE, which is why it is 14 slots
                //  and its neighbour is 18. The line runs straight on into the
                //  next — "ke-te-mu" answers "ke-te-mu" with nothing between
                //  them — so the rest that closes every other line would be a
                //  stumble in the middle of a phrase here.
                6, nil, 7, nil, 7, nil, 8, nil, 8, nil, 7, nil, 7, nil,
                // "ketemu pisan gawe gelo"  bilah 7  7  6  6  5  6  9
                //
                //  That closing 9 is the one note here nobody has checked at the
                //  instrument. It leaps up where the line has been falling, and
                //  the loop then drops a fifth back to the opening 5. If it is
                //  meant to be a 4 — the octave below — it is one digit here.
                6, nil, 6, nil, 5, nil, 5, nil, 4, nil, 5, nil, 8, nil,
                nil, nil, nil, nil,
            ],
            strokeMs: 250
        ),
    ]
}

/// Instrument-style bilah label: keys read 1…n, and the top key of a two-octave
/// set echoes the low "1" an octave up, shown as "1·" (matches the design).
func bilahLabel(_ index: Int, count: Int) -> String {
    if count >= 6 && index == count - 1 { return "1·" }
    return "\(index + 1)"
}

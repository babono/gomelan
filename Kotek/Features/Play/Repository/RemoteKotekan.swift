//
//  RemoteKotekan.swift
//  Kotek
//
//  A kotekan as the database holds it: two grids and the columns around them.
//  Plain values so it can cross between asynchronous tasks and the main actor.
//

import Foundation

nonisolated struct RemoteKotekan {
    var id: String
    var name: String
    var description: String?
    /// NULL marks a melody. The schema has no kind column — see `Kotekan(remote:)`.
    var level: Int?
    /// Per grid slot, the same number `Kotekan.makeSong` hands the engine.
    var bpm: Int
    var source: KotekanSource
    var instrumentID: String?
    var polos: [Int?]
    var sangsih: [Int?]
    var colotomic: [ColotomicHit]
    /// `Kotekan.polosDamp` / `sangsihDamp`, from `kotekan_hits.damp_slots`.
    var polosDamp: [Int?]?
    var sangsihDamp: [Int?]?

    init(
        id: String,
        name: String,
        description: String? = nil,
        level: Int? = nil,
        bpm: Int,
        source: KotekanSource,
        instrumentID: String? = nil,
        polos: [Int?],
        sangsih: [Int?],
        colotomic: [ColotomicHit] = [],
        polosDamp: [Int?]? = nil,
        sangsihDamp: [Int?]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.level = level
        self.bpm = bpm
        self.source = source
        self.instrumentID = instrumentID
        self.polos = polos
        self.sangsih = sangsih
        self.colotomic = colotomic
        self.polosDamp = polosDamp
        self.sangsihDamp = sangsihDamp
    }
}

nonisolated extension RemoteKotekan {
    /// Rebuild the two grids from the hit rows.
    ///
    /// Gong, kempur, klentong and kajar hits only come back on a player's own figure —
    /// see `Kotekan.colotomic`.
    init?(row: KotekanRow, hits: [KotekanHitRow]) {
        guard row.slotsPerCycle > 0, row.bpm > 0 else { return nil }
        var polos = [Int?](repeating: nil, count: row.slotsPerCycle)
        var sangsih = polos
        var polosDamp = [Int?](repeating: nil, count: row.slotsPerCycle)
        var sangsihDamp = polosDamp
        var colotomic: [ColotomicHit] = []
        for hit in hits where polos.indices.contains(hit.beatIndex) {
            switch hit.type {
            case "polos":
                polos[hit.beatIndex] = hit.keyIndex
                polosDamp[hit.beatIndex] = hit.dampSlots
            case "sangsih":
                sangsih[hit.beatIndex] = hit.keyIndex
                sangsihDamp[hit.beatIndex] = hit.dampSlots
            default:
                if let instrument = ColotomicInstrument(hitType: hit.type) {
                    colotomic.append(ColotomicHit(slot: hit.beatIndex, instrument: instrument))
                }
            }
        }
        self.init(
            id: row.id,
            name: row.name,
            description: row.description,
            level: row.level,
            bpm: row.bpm,
            source: row.source,
            instrumentID: row.instrumentID?.uuidString,
            polos: polos,
            sangsih: sangsih,
            colotomic: colotomic,
            polosDamp: polosDamp.contains { $0 != nil } ? polosDamp : nil,
            sangsihDamp: sangsihDamp.contains { $0 != nil } ? sangsihDamp : nil
        )
    }

    /// The other direction, for saving a figure from the Create Kotek flow.
    @MainActor
    init(_ k: Kotekan, source: KotekanSource, instrumentID: String?) {
        self.init(
            id: k.id,
            name: k.name,
            description: k.blurb,
            // NULL for a player's figure too: it has no rung, and `level` is
            // what the picker prints. `source` keeps it from reading back as a
            // melody — see `Kotekan(remote:)`.
            level: k.kind == .melody || k.source != .builtin ? nil : k.level,
            bpm: Int((60000.0 / Double(k.strokeMs)).rounded()),
            source: source,
            instrumentID: instrumentID,
            polos: k.polos,
            sangsih: k.sangsih,
            colotomic: k.colotomic,
            polosDamp: k.polosDamp,
            sangsihDamp: k.sangsihDamp
        )
    }
}

extension Kotekan {
    init(remote r: RemoteKotekan) {
        // The schema has no tone label or kind. A built-in takes its label from
        // the bundled copy of itself; a NULL level is what marks a melody, which
        // keeps "Level 0" off its card exactly as `KotekanKind` intends. Only
        // for built-ins: a player's figure has a NULL level too, and is still a
        // figure.
        let bundled = Kotekan.bundled.first { $0.id == r.id }
        self.init(
            id: r.id,
            name: r.name,
            level: r.level ?? 0,
            kind: r.level == nil && r.source == .builtin ? .melody : .figure,
            source: r.source,
            toneLabel: bundled?.toneLabel ?? (r.source == .automatic ? "Recorded" : "Your kotekan"),
            blurb: r.description ?? "",
            polos: r.polos,
            sangsih: r.sangsih,
            strokeMs: Int((60000.0 / Double(r.bpm)).rounded()),
            colotomic: r.source == .builtin ? Kotekan.builtinKajar(slots: r.polos.count) : r.colotomic,
            polosDamp: r.polosDamp,
            sangsihDamp: r.sangsihDamp
        )
    }

    /// Database figures in rail order: built-ins where `bundled` puts them —
    /// figures up the ladder, then the melodies — and the player's own after.
    static func catalogue(from remote: [RemoteKotekan]) -> [Kotekan] {
        let order = Dictionary(uniqueKeysWithValues: bundled.enumerated().map { ($1.id, $0) })
        return remote.map { Kotekan(remote: $0) }
            .sorted { (order[$0.id] ?? .max, $0.name) < (order[$1.id] ?? .max, $1.name) }
    }
}

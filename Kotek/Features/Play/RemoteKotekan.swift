//
//  RemoteKotekan.swift
//  Kotek
//
//  A kotekan as the database holds it: two grids and the columns around them.
//  Plain values so it can cross between asynchronous tasks and the main actor.
//

import Foundation

nonisolated struct RemoteKotekan: Sendable {
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

    init(
        id: String,
        name: String,
        description: String? = nil,
        level: Int? = nil,
        bpm: Int,
        source: KotekanSource,
        instrumentID: String? = nil,
        polos: [Int?],
        sangsih: [Int?]
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
    }
}

extension RemoteKotekan {
    /// Rebuild the two grids from the hit rows.
    ///
    /// Gong, kempur and kajar hits are read past for now: the play engine lays
    /// its own colotomic layer under every figure, so a figure that stores one
    /// would only be heard twice.
    init?(row: KotekanRow, hits: [KotekanHitRow]) {
        guard row.slotsPerCycle > 0, row.bpm > 0 else { return nil }
        var polos = [Int?](repeating: nil, count: row.slotsPerCycle)
        var sangsih = polos
        for hit in hits where polos.indices.contains(hit.beatIndex) {
            switch hit.type {
            case "polos": polos[hit.beatIndex] = hit.keyIndex
            case "sangsih": sangsih[hit.beatIndex] = hit.keyIndex
            default: continue
            }
        }
        self.init(id: row.id, name: row.name, description: row.description,
                  level: row.level, bpm: row.bpm, source: row.source,
                  instrumentID: row.instrumentID?.uuidString,
                  polos: polos, sangsih: sangsih)
    }

    /// The other direction, for saving a figure from the Create Kotek flow.
    init(_ k: Kotekan, source: KotekanSource, instrumentID: String?) {
        self.init(id: k.id, name: k.name, description: k.blurb,
                  level: k.kind == .melody ? nil : k.level,
                  bpm: Int((60000.0 / Double(k.strokeMs)).rounded()),
                  source: source, instrumentID: instrumentID,
                  polos: k.polos, sangsih: k.sangsih)
    }
}

extension Kotekan {
    init(remote r: RemoteKotekan) {
        //R The schema has no tone label or kind. A built-in takes its label from
        //R the bundled copy of itself; a NULL level is what marks a melody, which
        //R keeps "Level 0" off its card exactly as `KotekanKind` intends.
        let bundled = Kotekan.bundled.first { $0.id == r.id }
        self.init(id: r.id,
                  name: r.name,
                  level: r.level ?? 0,
                  kind: r.level == nil ? .melody : .figure,
                  toneLabel: bundled?.toneLabel ?? (r.source == .automatic ? "Recorded" : "Your kotekan"),
                  blurb: r.description ?? "",
                  polos: r.polos,
                  sangsih: r.sangsih,
                  strokeMs: Int((60000.0 / Double(r.bpm)).rounded()))
    }

    /// Database figures in rail order: built-ins where `bundled` puts them —
    /// figures up the ladder, then the melodies — and the player's own after.
    static func catalogue(from remote: [RemoteKotekan]) -> [Kotekan] {
        let order = Dictionary(uniqueKeysWithValues: bundled.enumerated().map { ($1.id, $0) })
        return remote.map { Kotekan(remote: $0) }
            .sorted { (order[$0.id] ?? .max, $0.name) < (order[$1.id] ?? .max, $1.name) }
    }
}

//
//  RemoteStore.swift
//  Kotek
//
//  The Supabase side of persistence. LOCAL-FIRST: `ProfileStore` stays the
//  source of truth and this is a copy written behind it, so a gangsa set up in
//  a hall with no signal still works, and a failed write never blocks a screen.
//
//  WHAT GOES UP. Instruments (name, type, key count), their keys (base_hz), the
//  kotekan catalogue (read), and one row per finished practice session.
//
//  WHAT STAYS ON THE PHONE, and why. Key rects and corners, fingerprints,
//  linear templates, the strike baseline and personal records have no columns
//  in the schema — and the geometry is only true for one camera on one stand
//  anyway. Move a phone to another device and the gangsa has to be re-aligned
//  regardless of what the database holds.
//
//  NO LOGIN. Every user is signed in ANONYMOUSLY on first launch: a real
//  `auth.uid()` with no screen in front of it, which is what the RLS policies
//  key on. When accounts arrive, that same user is linked to Apple / email
//  (`auth.linkIdentity`) and keeps everything it has written — nothing here has
//  to change for that.
//
//  An `actor` for the reason the others in this codebase are: network and JSON
//  stay off the main thread, and AppState only ever fires and forgets.
//

import Foundation
import OSLog
import Supabase

actor RemoteStore {
    /// Project URL and publishable key come from `Config.xcconfig`, through
    /// Info.plist, so a fork points at its own project without touching code.
    ///
    /// A missing value stops the app at launch rather than letting it run
    /// signed out: every write would fail quietly in the log, and a build with
    /// no backend would look exactly like a build with no signal.
    private let client: SupabaseClient = {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let urlString = info["SupabaseURL"] as? String,
              let url = URL(string: urlString), url.host() != nil,
              let key = info["SupabasePublishableKey"] as? String,
              !key.isEmpty, !key.hasPrefix("YOUR_")
        else {
            fatalError("Supabase is not configured: set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in Config.xcconfig (see Config.xcconfig.template).")
        }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
    }()

    private let log = Logger(subsystem: "Kotek", category: "remote")

    /// Kotekan ids that exist in the database. A practice session may only name
    /// one of these — the insert policy checks the kotekan row exists, so a
    /// session naming a figure that was never seeded is rejected WHOLE, not
    /// stored without it.
    private var knownKotekanIDs: Set<String> = []

    // MARK: - Auth

    /// The signed-in user, signing in anonymously the first time.
    ///
    /// Only a MISSING session leads to a new sign-in. An expired one that fails
    /// to refresh — offline, say — throws instead: signing in again there would
    /// mint a second anonymous user and orphan every row the first one wrote.
    func userID() async throws -> UUID {
        if client.auth.currentSession != nil {
            return try await client.auth.session.user.id
        }
        return try await client.auth.signInAnonymously().user.id
    }

    // MARK: - Instruments

    func saveInstrument(_ p: InstrumentProfile) async throws {
        //R Only instruments with a UUID id go up. The bundled default
        //R ("gangsa-exhibition-unit") is a placeholder, not something the
        //R player set up, and the column would reject its id anyway.
        guard let id = UUID(uuidString: p.id) else { return }
        let uid = try await userID()

        try await client.from("instruments")
            .upsert(InstrumentRow(id: id, userID: uid, name: p.name,
                                  type: p.type.rawValue,
                                  keyCount: p.keyCount, createdAt: p.createdAt))
            .execute()

        let keys = p.keys.map {
            InstrumentKeyRow(instrumentID: id, keyIndex: $0.index,
                             baseHz: $0.fundamentalHz > 0 ? Float($0.fundamentalHz) : nil)
        }
        if !keys.isEmpty {
            try await client.from("instrument_keys").upsert(keys).execute()
        }
        //R Keys past the count are left over from a resize down. Deleted rather
        //R than kept: index addresses the bilah, and a row for bilah 12 on a
        //R ten-key gangsa is a key that does not exist.
        try await client.from("instrument_keys")
            .delete()
            .eq("instrument_id", value: id)
            .gte("key_index", value: p.keyCount)
            .execute()
    }

    func deleteInstrument(id: String) async throws {
        guard let id = UUID(uuidString: id) else { return }
        _ = try await userID()
        //R Keys first: their policy looks the instrument up, so once it is gone
        //R they can no longer be reached to delete.
        try await client.from("instrument_keys").delete().eq("instrument_id", value: id).execute()
        try await client.from("instruments").delete().eq("id", value: id).execute()
    }

    // MARK: - Kotekan

    /// The built-in catalogue plus this user's own figures, as plain grids.
    /// `Kotekan(remote:)` turns them into figures on the main actor, where the
    /// model lives.
    ///
    /// Built-ins are readable without a session, so a failed sign-in still
    /// gets the catalogue — it just comes back without the player's own.
    func catalogue() async throws -> [RemoteKotekan] {
        do { _ = try await userID() } catch {
            log.error("sign-in failed, reading built-ins only: \(error.localizedDescription)")
        }

        let rows: [KotekanRow] = try await client.from("kotekan").select().execute().value
        guard !rows.isEmpty else { return [] }
        let hits: [KotekanHitRow] = try await client.from("kotekan_hits")
            .select()
            .in("kotekan_id", values: rows.map(\.id))
            .execute()
            .value

        knownKotekanIDs = Set(rows.map(\.id))
        let hitsByID = Dictionary(grouping: hits, by: \.kotekanID)
        return rows.compactMap { RemoteKotekan(row: $0, hits: hitsByID[$0.id] ?? []) }
    }

    /// A kotekan the player made — from the Create Kotek flow, tapped in by
    /// hand (`.manual`) or recorded off the sensors (`.automatic`).
    func saveKotekan(_ k: RemoteKotekan) async throws {
        let uid = try await userID()
        try await client.from("kotekan")
            .upsert(KotekanRow(id: k.id, userID: uid,
                               instrumentID: k.instrumentID.flatMap(UUID.init(uuidString:)),
                               name: k.name, description: k.description, level: k.level,
                               slotsPerCycle: k.polos.count, bpm: k.bpm, source: k.source))
            .execute()

        //R Replaced, not upserted: a slot that became a rest has to lose its row,
        //R and upsert can only ever add or change one.
        try await client.from("kotekan_hits").delete().eq("kotekan_id", value: k.id).execute()
        let hits = [("polos", k.polos), ("sangsih", k.sangsih)].flatMap { type, grid in
            grid.enumerated().compactMap { slot, key in
                key.map { KotekanHitRow(kotekanID: k.id, type: type, beatIndex: slot, keyIndex: $0) }
            }
        }
        if !hits.isEmpty {
            try await client.from("kotekan_hits").insert(hits).execute()
        }
        knownKotekanIDs.insert(k.id)
    }

    // MARK: - Practice sessions

    /// File a finished session. The instrument goes up first, in the same call,
    /// because the insert policy checks the player owns it — a session that
    /// raced ahead of its instrument's first sync would be refused.
    func recordSession(_ s: PracticeSession, on instrument: InstrumentProfile) async throws {
        try await saveInstrument(instrument)
        let uid = try await userID()
        let row = PracticeSessionRow(
            userID: uid,
            kotekanID: s.kotekanID.flatMap { knownKotekanIDs.contains($0) ? $0 : nil },
            instrumentID: UUID(uuidString: instrument.id),
            session: s
        )
        try await client.from("practice_session").insert(row).execute()
    }
}

// MARK: - What a session reports

/// One finished practice session, in the app's terms. `RemoteStore` adds the
/// user and resolves the ids.
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
}

extension PracticeSession {
    init(result: SongResult, kotekan: Kotekan?, half: KotekanHalf,
         tempoScale: Double, leniency: Double) {
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

// MARK: - Rows
//
// `nonisolated` because this target defaults to MainActor, and a main-actor
// Codable conformance cannot be used by the client's decoder off the main
// thread. Explicit CodingKeys rather than a snake_case strategy: the client's
// encoder is shared, and the column names are the contract.

enum KotekanSource: String, Codable, Sendable {
    case builtin, manual, automatic
}

nonisolated private struct InstrumentRow: Codable, Sendable {
    var id: UUID
    var userID: UUID
    var name: String
    var type: String
    var keyCount: Int
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, type
        case userID = "user_id"
        case keyCount = "key_count"
        case createdAt = "created_at"
    }
}

/// Only the columns the app owns. `sensor_id`, `sensor_threshold` and
/// `sample_path` are left out of the payload entirely, so an upsert from here
/// never overwrites what the sensor setup writes into them.
nonisolated private struct InstrumentKeyRow: Encodable, Sendable {
    var instrumentID: UUID
    var keyIndex: Int
    var baseHz: Float?

    enum CodingKeys: String, CodingKey {
        case instrumentID = "instrument_id"
        case keyIndex = "key_index"
        case baseHz = "base_hz"
    }

    //R Written by hand to send an explicit null. Synthesized encoding OMITS a
    //R nil, and PostgREST refuses a bulk upsert whose rows disagree on keys —
    //R so one uncalibrated key would sink the whole instrument's write.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(instrumentID, forKey: .instrumentID)
        try c.encode(keyIndex, forKey: .keyIndex)
        try c.encode(baseHz, forKey: .baseHz)
    }
}

nonisolated private struct KotekanRow: Codable, Sendable {
    var id: String
    var userID: UUID?
    var instrumentID: UUID?
    var name: String
    var description: String?
    var level: Int?
    var slotsPerCycle: Int
    var bpm: Int
    var source: KotekanSource

    enum CodingKeys: String, CodingKey {
        case id, name, description, level, bpm, source
        case userID = "user_id"
        case instrumentID = "instrument_id"
        case slotsPerCycle = "slots_per_cycle"
    }
}

nonisolated private struct KotekanHitRow: Codable, Sendable {
    var kotekanID: String
    /// `hit_type`: polos | sangsih | gong | kempur | kajar.
    var type: String
    var beatIndex: Int
    var keyIndex: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case kotekanID = "kotekan_id"
        case beatIndex = "beat_index"
        case keyIndex = "key_index"
    }
}

nonisolated private struct PracticeSessionRow: Encodable, Sendable {
    var userID: UUID
    var kotekanID: String?
    var instrumentID: UUID?
    var session: PracticeSession

    enum CodingKeys: String, CodingKey {
        case half, bpm, leniency, accuracy
        case userID = "user_id"
        case kotekanID = "kotekan_id"
        case instrumentID = "instrument_id"
        case tempoScale = "tempo_scale"
        case cycleCount = "cycle_count"
        case onTimeCount = "on_time_count"
        case wrongKeyCount = "wrong_key_count"
        case missedCount = "missed_count"
        case landedNotes = "landed_notes"
        case bestStreak = "best_streak"
        case driftMs = "drift_ms"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userID, forKey: .userID)
        try c.encodeIfPresent(kotekanID, forKey: .kotekanID)
        try c.encodeIfPresent(instrumentID, forKey: .instrumentID)
        try c.encode(session.half, forKey: .half)
        try c.encode(session.bpm, forKey: .bpm)
        try c.encode(session.tempoScale, forKey: .tempoScale)
        try c.encode(session.leniency, forKey: .leniency)
        try c.encode(session.cycleCount, forKey: .cycleCount)
        try c.encodeIfPresent(session.accuracy, forKey: .accuracy)
        try c.encode(session.onTimeCount, forKey: .onTimeCount)
        try c.encode(session.wrongKeyCount, forKey: .wrongKeyCount)
        try c.encode(session.missedCount, forKey: .missedCount)
        try c.encode(session.landedNotes, forKey: .landedNotes)
        try c.encode(session.bestStreak, forKey: .bestStreak)
        try c.encodeIfPresent(session.driftMs, forKey: .driftMs)
    }
}

// MARK: - Kotekan, in database terms

/// A kotekan as the database holds it: two grids and the columns around them.
/// Plain values so it can cross between the actor and the main actor — the
/// `Kotekan` model is main-actor isolated, like everything in this target.
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
}

private extension RemoteKotekan {
    /// Rebuild the two grids from the hit rows.
    ///
    /// Gong, kempur and kajar hits are read past for now: the play engine lays
    /// its own colotomic layer under every figure, so a figure that stores one
    /// would only be heard twice.
    nonisolated init?(row: KotekanRow, hits: [KotekanHitRow]) {
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
}

extension RemoteKotekan {
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

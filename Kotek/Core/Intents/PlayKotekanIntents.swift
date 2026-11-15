//
//  PlayKotekanIntents.swift
//  Kotek
//
//  Created by Dimas Nugraha on 04/10/26.
//

import AppIntents

struct KotekanEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Kotekan"
    static let defaultQuery = KotekanQuery()

    let id: String
    let name: String
    /// "60 BPM · 4 s cycle", as the picker shows it.
    let spec: String

    init(_ k: Kotekan) {
        id = k.id
        name = k.name
        spec = k.specLabel
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(spec)"
        )
    }
}

/// The picker's whole catalogue — the built-ins and the player's own
/// patterns from Create — not just `Kotekan.bundled`, which left anything the
/// player had made out of reach of Siri and Shortcuts.
struct KotekanQuery: EntityStringQuery {
    @Dependency var app: AppState

    @MainActor
    func entities(for identifiers: [String]) async throws -> [KotekanEntity] {
        app.kotekans.filter { identifiers.contains($0.id) }.map(KotekanEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [KotekanEntity] {
        app.kotekansOnGangsa.filter {
            $0.name.localizedCaseInsensitiveContains(string)
        }.map(KotekanEntity.init)
    }

    /// Only what fits the gangsa in use, as the picker shows it.
    @MainActor
    func suggestedEntities() async throws -> [KotekanEntity] {
        app.kotekansOnGangsa.filter { app.kotekan($0, playableOn: app.profile) }.map(KotekanEntity.init)
    }
}

struct PlayKotekanIntents: AppIntent {
    static let title: LocalizedStringResource = "Play Kotekan"
    static let supportedModes: IntentModes = .foreground

    @Dependency var app: AppState

    @Parameter(title: "Play Kotekan", requestValueDialog: "Which Kotekan?")
    var kotekan: KotekanEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Practice \(\.$kotekan)")
    }

    @MainActor
    func perform() throws -> some IntentResult {
        guard let full = app.kotekans.first(where: { $0.id == kotekan.id }) else {
            throw $kotekan.needsValueError()
        }
        // Matched by name, so a pattern too wide for this gangsa can still be
        // asked for; the picker would have greyed it out.
        guard app.kotekan(full, playableOn: app.profile) else {
            throw TooFewKeys(pattern: full.name, gangsa: app.profile.name)
        }
        app.playKotekan(full)
        return .result()
    }
}

private struct TooFewKeys: Error, CustomLocalizedStringResourceConvertible {
    let pattern: String
    let gangsa: String

    var localizedStringResource: LocalizedStringResource {
        "\(pattern) needs more keys than \(gangsa) has."
    }
}

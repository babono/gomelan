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
    let level: Int
    let toneLabel: String

    init(_ k: Kotekan) {
        self.id = k.id
        self.name = k.name
        self.level = k.level
        self.toneLabel = k.toneLabel
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "Level \(level) - \(toneLabel)"
        )
    }
}

struct KotekanQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [KotekanEntity] {
        await Kotekan.bundled.filter { identifiers.contains($0.id) }.map(
            KotekanEntity.init
        )

    }

    func entities(matching string: String) async throws
        -> [KotekanEntity]
    {
        await Kotekan.bundled.filter {
            $0.name.localizedCaseInsensitiveContains(string)
        }.map(KotekanEntity.init)
    }

    func suggestedEntities() async throws -> [KotekanEntity] {
        await Kotekan.bundled.map(KotekanEntity.init)
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
        guard let full = Kotekan.bundled.first(where: { $0.id == kotekan.id })
        else {
            throw $kotekan.needsValueError()
        }
        app.chooseKotekan(full)
        return .result()
    }
}

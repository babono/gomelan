//
//  NavigateScreenIntents.swift
//  Kotek
//
//  Created by Dimas Nugraha on 04/10/26.
//

import AppIntents
import FactoryKit

struct NavigateScreenIntents: AppIntent {
    static let title: LocalizedStringResource = "Navigate to Screen"

    static let supportedModes: IntentModes = .foreground

    @Dependency private var app: AppState

    @Parameter(
        title: "Screen", requestValueDialog: "Which Screen?"
    ) var navigationOptions: Destination

    static var parameterSummary: some ParameterSummary {
        Summary("Navigate to \(\.$navigationOptions)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        switch navigationOptions {
        case .patterns: app.backToKotekan()
        case .create: app.openCreateKotek()
        case .history: app.openHistory()
        case .settings: app.openSettings()
        case .gangsa: app.openChooseInstrument()
        }
        return .result()
    }
}

/// The screens that stand on their own. This used to be every `Route`, and
/// most of those need a session behind them: "Go to Results" with nothing
/// played opened an empty screen, and the debug tools were one sentence away.
/// Each case opens through the same `AppState` call its button uses.
enum Destination: String, AppEnum {
    case patterns
    case create
    case history
    case settings
    case gangsa

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Screen"

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .patterns: DisplayRepresentation(title: "Patterns", synonyms: ["Kotekan", "Choose Kotekan"]),
        .create: DisplayRepresentation(title: "Create Kotek", synonyms: ["Create", "Kotek Studio"]),
        .history: DisplayRepresentation(title: "Practice History", synonyms: ["History"]),
        .settings: "Settings",
        .gangsa: DisplayRepresentation(title: "Gangsa", synonyms: ["Instruments", "Choose Instrument"])
    ]
}

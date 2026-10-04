//
//  Shortcuts.swift
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
    ) var navigationOptions: AppState.Screen
    
    static var parameterSummary: some ParameterSummary {
        Summary("Navigate to \(\.$navigationOptions)")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult {
        app.screen = navigationOptions
        return .result()
    }
}

//
//  AppShortcuts.swift
//  Kotek
//
//  Created by Dimas Nugraha on 04/10/26.
//

import AppIntents

struct AppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayKotekanIntents(),
            phrases: [
                "Practice \(\.$kotekan) in \(.applicationName)",
                "Play \(\.$kotekan) in \(.applicationName)",
                "Practice in \(.applicationName)"
            ],
            shortTitle: "Play Kotekan",
            systemImageName: "music.note"
        )
        AppShortcut(
            intent: NavigateScreenIntents(),
            phrases: [
                "Go To \(\.$navigationOptions) in \(.applicationName)"
            ],
            shortTitle: "Navigate to",
            systemImageName: "arrow.right.circle    "
        )
    }
}

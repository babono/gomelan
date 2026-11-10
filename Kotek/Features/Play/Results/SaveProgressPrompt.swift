//
//  SaveProgressPrompt.swift
//  Kotek
//
//  The one-time "keep this" ask for guests, over the results screen.
//

import SwiftUI

struct SaveProgressPrompt: View {
    @Environment(AppState.self) private var app

    var body: some View {
        LinkApplePrompt(
            title: app.lastSetRecord ? "New record — keep it?" : "Keep your progress?",
            message: "As a guest, your gangsa and records are only on this iPhone. Link an Apple ID to keep them if you delete the app or change phones.",
            origin: .results
        ) {
            app.dismissSavePrompt()
        }
    }
}

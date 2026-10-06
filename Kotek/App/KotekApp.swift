//
//  KotekApp.swift
//  Kotek
//
//  Play gamelan anywhere — no sekaa required.
//

import SwiftUI
import FactoryKit
import AppIntents

@main
struct KotekApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app: AppState

    init() {
        // The audio session is the fiddliest piece of the project. The app opens
        // on the playback configuration, because the splash and title screens
        // only make sound and `.measurement` mode — which capture requires —
        // attenuates output badly enough to lose a gong entirely.
        //
        // The capture configuration (PRD §13.2) goes back on before anything
        // listens: on leaving the title screen, and again inside
        // `AudioEngineController.start`, which is the one door every listening
        // path goes through.
        AudioSessionManager.configureForPlayback()
        
        let appState = AppState()
        _app = State(initialValue: appState)
        
        // App Intents
        AppDependencyManager.shared.add(dependency: appState)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
    }
}

/// Landscape-locked during the whole experience (PRD §6.2, §13.1).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .landscape
    }
}

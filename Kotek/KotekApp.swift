//
//  KotekApp.swift
//  Kotek
//
//  Play gamelan anywhere — no sekaa required.
//

import SwiftUI

@main
struct KotekApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
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

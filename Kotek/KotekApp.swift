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
        // The audio session is the fiddliest piece of the project — configure it
        // once at launch, before any capture (PRD §13.2).
        AudioSessionManager.configure()
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

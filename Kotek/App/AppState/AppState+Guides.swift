//
//  AppState+Guides.swift
//  Kotek
//
//  Onboarding walkthrough, permissions, and contextual explainers.
//

import Foundation

extension AppState {
    // MARK: - Onboarding & Permissions

    /// Always the instrument list, even when it is empty.
    func begin() {
        savedProfiles = ProfileStore.loadAll()
        screen = .chooseInstrument
    }

    func permissionsResolved(granted: Bool) {
        screen = granted ? .chooseInstrument : .permissionsBlocked
    }

    /// Asked for — from the help button on the instrument picker.
    func openOnboarding() {
        showingOnboarding = true
    }

    /// Unasked, once. Called when the splash hands over.
    func showOnboardingIfFirstRun() {
        guard !hasSeenOnboarding else { return }
        showingOnboarding = true
    }

    func closeOnboarding() {
        showingOnboarding = false
        guard !hasSeenOnboarding else { return }
        hasSeenOnboarding = true
        Defaults.set("hasSeenOnboarding", true)
    }

    // MARK: - Practice Coach

    func markPracticeCoachSeen() {
        guard !hasSeenPracticeCoach else { return }
        hasSeenPracticeCoach = true
        Defaults.set("hasSeenPracticeCoach", true)
    }

    // MARK: - Contextual Guides

    func openGuide(_ guide: Guide) {
        visibleGuide = guide
    }

    func closeGuide() {
        if let visibleGuide { markSeen(visibleGuide) }
        visibleGuide = nil
    }

    /// Show it unprompted the first time, and only the first time.
    func showGuideIfFirstRun(_ guide: Guide) {
        guard !seen.contains(guide.rawValue), visibleGuide == nil else {
            return
        }
        visibleGuide = guide
    }

    func markSeen(_ guide: Guide) {
        guard !seen.contains(guide.rawValue) else { return }
        seen.insert(guide.rawValue)
        Defaults.set(guide.seenKey, true)
    }
}

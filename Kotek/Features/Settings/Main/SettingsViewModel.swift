//
//  SettingsViewModel.swift
//  Kotek
//
//  ViewModel for Settings: which page the sidebar has open, the gangsa name
//  being typed, and the account and gangsa actions.
//

import CoreGraphics
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class SettingsViewModel {
    let app: AppState

    var draftName: String = ""
    var showDeleteConfirm = false
    var showSignOutConfirm = false
    var showDeleteAccountConfirm = false
    @ObservationIgnored private let reauthorization = AppleReauthorization()

    /// Opens on the gangsa being played, the thing most often changed.
    var page: SettingsPage

    init(app: AppState) {
        self.app = app
        draftName = app.profile.name
        page = .gangsa(app.profile.id)
    }

    /// A gangsa's page shows the active one (the gangsa card reads
    /// `app.profile`), so picking it makes it active — as centring it in the
    /// picker does.
    func open(_ page: SettingsPage) {
        if case let .gangsa(id) = page, id != app.profile.id,
           let p = app.savedProfiles.first(where: { $0.id == id })
        {
            app.activateInstrument(p)
        }
        self.page = page
    }

    func updateActiveProfileId() {
        draftName = app.profile.name
    }

    func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draftName = app.profile.name
            return
        }
        guard trimmed != app.profile.name else { return }
        var updated = app.profile
        updated.name = trimmed
        app.profile = updated
        app.saveInstrument(updated)
    }

    func deleteInstrument() {
        app.deleteInstrument(app.profile.id)
        app.openChooseInstrument()
    }

    /// Confirmed in the dialog; Apple's sheet is the second confirmation, and
    /// closing it calls the whole thing off.
    func deleteAccount() {
        Task {
            do {
                guard let code = try await reauthorization.authorizationCode() else { return }
                await app.deleteAccount(appleAuthorizationCode: code)
            } catch {
                app.accountError = String(localized: "Couldn't confirm with Apple. Try again.")
            }
        }
    }
}

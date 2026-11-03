//
//  SettingsTypes.swift
//  Kotek
//
//  Section definitions and scroll tracking metrics for Settings.
//

import Foundation

/// What the sidebar can open. The gangsa page is the one being played:
/// another is edited by switching to it ("Switch gangsa" on that page).
///
/// R Settings was one long scroll, every card stacked, with a rail of chips
/// R that followed along. With several gangsa that read as one gangsa's card
/// R among the app's; a sidebar lists them as what they are.
/// R The sidebar first listed EVERY gangsa, picking one making it active.
/// R Tried on the iPad, it was not liked: changing a gangsa that is not the
/// R one in play is now a switch away, as everywhere else in the app.
enum SettingsPage: Hashable {
    case gangsa
    case practice
    case account
    case debug
}

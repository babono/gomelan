//
//  SettingsTypes.swift
//  Kotek
//
//  Section definitions and scroll tracking metrics for Settings.
//

import Foundation

/// What the sidebar can open. A gangsa is a page of its own, so each one
/// is reached by name rather than through "the current gangsa".
///
/// R Settings was one long scroll, every card stacked, with a rail of chips
/// R that followed along. With several gangsa that read as one gangsa's card
/// R among the app's; a sidebar lists them as what they are.
enum SettingsPage: Hashable {
    case gangsa(String)
    case practice
    case account
    case debug
}

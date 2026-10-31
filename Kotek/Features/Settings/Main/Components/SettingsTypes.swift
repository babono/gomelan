//
//  SettingsTypes.swift
//  Kotek
//
//  Section definitions and scroll tracking metrics for Settings.
//

import CoreGraphics
import Foundation

/// The settings sections, in the order they are laid out.
/// `allCases` IS the running order — the rail reads "where am I" as the last
/// case whose card has passed the top of the screen.
enum SettingsSection: String, CaseIterable, Identifiable {
    case account, instrument, deprecated, debug

    var id: String {
        rawValue
    }

    /// The card heading. `.instrument` has none here: it is headed with the
    /// gangsa's name, which only the view can supply.
    var title: String {
        switch self {
        case .account: String(localized: "Account")
        case .instrument: ""
        case .deprecated: String(localized: "Deprecated")
        case .debug: String(localized: "Debug")
        }
    }

    /// The rail label. The same as the heading now every heading is one word.
    var chip: String {
        title
    }
}

/// The scroll positions the rail watches, kept OUT of view state on purpose.
@MainActor
final class SectionMetrics {
    var frames: [SettingsSection: CGRect] = [:]
}

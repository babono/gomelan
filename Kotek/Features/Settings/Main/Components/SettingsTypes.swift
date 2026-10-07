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
    case instrument, debug, tempo, audio, judging, camera, detection

    var id: String {
        rawValue
    }

    /// The card heading. `.instrument` has none here: it is headed with the
    /// gangsa's name, which only the view can supply.
    var title: String {
        switch self {
        case .instrument: ""
        case .debug: "Debug"
        case .tempo: "Practice tempo"
        case .audio: "Audio cues"
        case .judging: "Judging"
        case .camera: "Camera"
        case .detection: "Detection"
        }
    }

    /// The rail label — shorter than the heading where the heading has room to
    /// be a sentence and the chip does not.
    var chip: String {
        switch self {
        case .tempo: "Tempo"
        case .audio: "Audio"
        default: title
        }
    }
}

/// The scroll positions the rail watches, kept OUT of view state on purpose.
@MainActor
final class SectionMetrics {
    var frames: [SettingsSection: CGRect] = [:]
}

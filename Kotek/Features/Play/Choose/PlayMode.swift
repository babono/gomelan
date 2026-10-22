//
//  PlayMode.swift
//  Kotek
//
//  Solo or co-op, chosen before the pattern rather than after it. Co-op was
//  a button beside the carousel that left at once for the setup, so the two
//  ways into a pattern were two different gestures; now it is a setting in
//  the corner and the card is always what you tap to go on.
//

enum PlayMode: String, CaseIterable {
    case solo
    case coop

    var title: String {
        switch self {
        case .solo: "Solo"
        case .coop: "Co-op"
        }
    }
}

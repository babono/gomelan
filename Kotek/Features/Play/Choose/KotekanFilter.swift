//
//  KotekanFilter.swift
//  Kotek
//
//  The pills under the kotekan rail. They replaced a search field: with a
//  handful of patterns nobody typed a name, but "which ones haven't I
//  learned?" and "where are the ones I made?" were questions the rail could
//  only answer by swiping through all of it.
//

import Foundation

enum KotekanFilter: CaseIterable {
    case all, new, learned, mine

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .new: String(localized: "New")
        case .learned: String(localized: "Learned")
        case .mine: String(localized: "My kotek")
        }
    }

    /// "New" and "Learned" are the built-ins, split by whether Learn was
    /// finished on this device (`LearnProgress`); the player's own figures
    /// are only ever under "My kotek".
    func includes(_ kotekan: Kotekan) -> Bool {
        switch self {
        case .all: true
        case .new: kotekan.source == .builtin && !LearnProgress.isDone(kotekan.id)
        case .learned: kotekan.source == .builtin && LearnProgress.isDone(kotekan.id)
        case .mine: kotekan.source != .builtin
        }
    }
}

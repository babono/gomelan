//
//  DampGuide.swift
//  Kotek
//
//  How much of the damping guide the practice screens show (§5.5): the hand
//  tile that falls behind each stroke, and the thumb pinching the bar as the
//  note ends. Display only — damping is never judged.
//
//  Three steps, not a switch: players who have damping in their hands asked
//  to lose the falling tiles, which crowd the lanes, and still see the
//  thumb, which only moves at the bar.
//

enum DampGuide: String, CaseIterable {
    case all
    case handOnly
    case off

    var title: String {
        switch self {
        case .all: "Blocks + hand"
        case .handOnly: "Hand only"
        case .off: "Off"
        }
    }

    /// The tiles on the waterfall.
    var showsTiles: Bool {
        self == .all
    }

    /// The thumb and the dimmed bar on the gangsa.
    var showsHand: Bool {
        self != .off
    }
}

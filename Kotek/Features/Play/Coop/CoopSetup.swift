//
//  CoopSetup.swift
//  Kotek
//
//  One-screen coop (PRD v2 §6.6.3): two players, each at their own gangsa,
//  one device between them showing both halves. Who sits where, who plays
//  which half, and on which gangsa.
//

import Foundation

struct CoopPlayer: Equatable {
    var name: String
    /// One of this device's gangsa. Two players can share a profile: a pair
    /// of gangsa is tuned and sized as one, so most groups set up only one.
    var instrumentID: String
    var half: KotekanHalf
}

struct CoopSetup: Equatable {
    /// Seat order, as the players sit in front of the screen. The lanes are
    /// drawn in this order so each player reads the lane on their own side.
    var left: CoopPlayer
    var right: CoopPlayer
    /// Off by default: the partner is real now, and a recorded voice under
    /// two live players is a third player out of step with both.
    var guideVoices = false

    /// Player 1 on the active gangsa, polos; player 2 beside them, sangsih —
    /// the default the PRD sets, one tap from either swap.
    init(playerName: String?, instrumentID: String) {
        left = CoopPlayer(name: playerName ?? "Player 1", instrumentID: instrumentID, half: .polos)
        right = CoopPlayer(name: "Player 2", instrumentID: instrumentID, half: .sangsih)
    }

    var players: [CoopPlayer] {
        [left, right]
    }

    mutating func swapHalves() {
        (left.half, right.half) = (right.half, left.half)
    }

    mutating func swapSeats() {
        swap(&left, &right)
    }
}

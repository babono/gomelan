//
//  AppState+Coop.swift
//  Kotek
//
//  One-screen coop (PRD v2 §6.6.3): into the setup from the kotekan picker,
//  out to the shared waterfall, and back.
//

import Foundation

extension AppState {
    /// From the picker's Coop button, with the figure it was on.
    func openCoop(_ k: Kotekan) {
        selectedKotekan = k
        if coop == nil {
            coop = CoopSetup(playerName: playerName, instrumentID: profile.id)
        }
        screen = .coopSetup
    }

    /// The gangsa a player sits at. Falls back to the active one: a profile
    /// deleted since the setup was made must not leave a lane with no
    /// instrument to draw.
    func coopProfile(_ player: CoopPlayer) -> InstrumentProfile {
        savedProfiles.first { $0.id == player.instrumentID } ?? profile
    }

    /// Only figures both gangsa can play (§6.6.2).
    func coopPlayable(_ k: Kotekan) -> Bool {
        guard let coop else { return false }
        return coop.players.allSatisfy { kotekan(k, playableOn: coopProfile($0)) }
    }

    func startCoop() {
        screen = .coopPlay
    }

    /// Back to the setup rather than the picker: the next thing a pair does
    /// after a run is usually swap halves and go again.
    func leaveCoop() {
        screen = .coopSetup
    }
}

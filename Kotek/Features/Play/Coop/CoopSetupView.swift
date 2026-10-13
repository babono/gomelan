//
//  CoopSetupView.swift
//  Kotek
//
//  Before one-screen coop: who sits where, who plays which half, on which
//  gangsa, and how fast (§6.6.2–3). Binds straight to `AppState.coop` — there
//  is nothing here a ViewModel would add.
//

import SwiftUI

struct CoopSetupView: View {
    @Environment(AppState.self) private var app

    /// Never nil on this screen — `openCoop` makes it — but a binding has to
    /// say what it would be.
    private var setup: Binding<CoopSetup> {
        Binding(
            get: { app.coop ?? CoopSetup(playerName: app.playerName, instrumentID: app.profile.id) },
            set: { app.coop = $0 }
        )
    }

    var body: some View {
        @Bindable var bindableApp = app

        VStack(spacing: 0) {
            TopBar(title: "Play together", onBack: { app.backToKotekan() })

            VStack(spacing: 18) {
                if let k = app.selectedKotekan {
                    VStack(spacing: 2) {
                        Text(k.catalogLabel)
                            .font(.sans(12, weight: .medium))
                            .textCase(.uppercase)
                            .tracking(1.5)
                            .foregroundStyle(Theme.stone)
                        Text(k.name)
                            .font(.serif(28))
                            .foregroundStyle(Theme.cream)
                    }
                }

                HStack(spacing: 14) {
                    PlayerCard(
                        player: setup.left,
                        profiles: app.savedProfiles,
                        profile: app.coopProfile(setup.wrappedValue.left)
                    )
                    Button {
                        withAnimation(.snappy) { setup.wrappedValue.swapSeats() }
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.symbol(15, weight: .semibold))
                            .foregroundStyle(Theme.cream.opacity(0.8))
                            .frame(width: 44, height: 44)
                            .overlay(Circle().strokeBorder(Theme.cream.opacity(0.22), lineWidth: 1))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.kajar)
                    .accessibilityLabel("Swap seats")
                    PlayerCard(
                        player: setup.right,
                        profiles: app.savedProfiles,
                        profile: app.coopProfile(setup.wrappedValue.right)
                    )
                }

                HStack(spacing: 14) {
                    PillButton(
                        title: "Swap halves",
                        systemImage: "arrow.up.arrow.down",
                        style: .outlined,
                        compact: true
                    ) {
                        withAnimation(.snappy) { setup.wrappedValue.swapHalves() }
                    }
                    TempoPicker(tempoScale: $bindableApp.tempoScale)
                        .fixedSize()
                    Toggle("Guide voices", isOn: setup.guideVoices)
                        .font(.sans(14))
                        .foregroundStyle(Theme.cream)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 28)
            .frame(maxHeight: .infinity)

            footer
        }
    }

    private var footer: some View {
        let k = app.selectedKotekan
        let playable = k.map(app.coopPlayable) ?? false
        return HStack(spacing: 14) {
            Text(playable || k == nil
                ? "Sensors aren't used together yet. Play along — nothing is scored."
                : "\(k!.name) needs \(k!.requiredKeys) bilah on both gangsa.")
                .font(.sans(13))
                .foregroundStyle(playable ? Theme.cream.opacity(0.45) : Theme.wrong)
            Spacer()
            PillButton(
                title: "Start",
                trailingSystemImage: "arrow.right",
                style: .filled,
                compact: true
            ) {
                app.startCoop()
            }
            .disabled(!playable)
            .opacity(playable ? 1 : 0.4)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 10)
    }
}

private struct PlayerCard: View {
    @Binding var player: CoopPlayer
    let profiles: [InstrumentProfile]
    /// The gangsa `player` resolves to — the active one if theirs is gone.
    let profile: InstrumentProfile
    @FocusState private var nameFocused: Bool

    var body: some View {
        let colour = player.half == .polos ? Theme.polosVoice : Theme.sangsihVoice
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(player.half.title)
                    .font(.serif(26))
                    .foregroundStyle(colour)
                Text(player.half.eyebrow)
                    .font(.sans(12))
                    .foregroundStyle(Theme.cream.opacity(0.5))
            }

            TextField("Name", text: $player.name)
                .textFieldStyle(.plain)
                .font(.serif(20))
                .foregroundStyle(Theme.cream)
                .focused($nameFocused)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.deep.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.radius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius)
                        .strokeBorder(
                            nameFocused ? Theme.buttonFill : Theme.cream.opacity(0.15),
                            lineWidth: nameFocused ? 2 : 1
                        )
                )
                .onSubmit { nameFocused = false }
                .onChange(of: player.name) { _, new in
                    if new.count > 24 { player.name = String(new.prefix(24)) }
                }

            // ponytail: one of this device's gangsa only. Quick-adding a
            // visitor's gangsa (§6.6.3) waits for the sensors, which are what
            // would make its key map matter.
            Menu {
                ForEach(profiles) { p in
                    Button {
                        player.instrumentID = p.id
                    } label: {
                        if p.id == profile.id {
                            Label("\(p.name) · \(p.keyCount) bilah", systemImage: "checkmark")
                        } else {
                            Text("\(p.name) · \(p.keyCount) bilah")
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pianokeys")
                        .font(.symbol(12, weight: .semibold))
                    Text("\(profile.name) · \(profile.keyCount) bilah")
                        .font(.sans(13, weight: .medium))
                        .lineLimit(1)
                    if profiles.count > 1 {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.symbol(9, weight: .semibold))
                    }
                }
                .foregroundStyle(Theme.copper)
            }
            .disabled(profiles.count < 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.deep.opacity(0.45), in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(colour.opacity(0.5), lineWidth: 1)
        )
    }
}

//
//  VoiceMixer.swift
//  Kotek
//
//  The voice mixer allows listening to your half, your partner's half,
//  or muting either voice during practice.
//

import SwiftUI

/// The legend IS the mixer. Each colour names a voice on the score, and tapping
/// it silences that voice — so a figure can be learned by hearing it played
/// first, then heard against the other half once it is in the hands.
struct VoiceMixer: View {
    let yourHalf: KotekanHalf
    /// ON by default: you cannot copy what you have not heard. Mute it once the
    /// figure is in your hands and the only polos in the room is yours.
    @Binding var yourVoiceAudible: Bool
    @Binding var partnerAudible: Bool

    var body: some View {
        HStack(spacing: 8) {
            chip(
                color: colour(for: yourHalf),
                label: "\(yourHalf.title) · you",
                isOn: $yourVoiceAudible
            )
            chip(
                color: colour(for: yourHalf.other),
                label: yourHalf.other.title,
                isOn: $partnerAudible
            )
        }
    }

    private func colour(for half: KotekanHalf) -> Color {
        half == .polos ? Theme.polosVoice : Theme.sangsihVoice
    }

    private func chip(color: Color, label: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(isOn.wrappedValue ? 0.95 : 0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(color.opacity(isOn.wrappedValue ? 0 : 0.6), lineWidth: 1)
                    )
                    .frame(width: 12, height: 8)

                Text(label)
                    .font(.sans(11, weight: .medium))
                    .foregroundStyle(isOn.wrappedValue ? Theme.cream : Theme.inkStone.opacity(0.7))

                Image(systemName: isOn.wrappedValue ? "speaker.wave.1.fill" : "speaker.slash.fill")
                    .font(.sans(9))
                    .foregroundStyle(isOn.wrappedValue ? color : Theme.inkStone.opacity(0.7))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(isOn.wrappedValue ? Theme.ink.opacity(0.55) : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.inkStone.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.kajar)
    }
}

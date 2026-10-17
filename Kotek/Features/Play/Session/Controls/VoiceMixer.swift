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
///
/// No speaker glyph on the chips. It made them read as mute switches first and
/// as the score's legend second, which is the wrong way round; a silenced voice
/// shows as a hollow swatch and dimmed name instead. It replaced a Voices
/// dropdown on the waterfall, which hid both voices behind a menu.
struct VoiceMixer: View {
    let yourHalf: KotekanHalf
    /// ON by default: you cannot copy what you have not heard. Mute it once the
    /// figure is in your hands and the only polos in the room is yours.
    @Binding var yourVoiceAudible: Bool
    @Binding var partnerAudible: Bool

    var body: some View {
        HStack(spacing: Theme.controlSpacing) {
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

    /// A button, not a chip: both voices are normally ON, and two selected
    /// chips side by side would shout. A silenced voice shows as a hollow swatch
    /// and a dimmed button instead.
    private func chip(color: Color, label: String, isOn: Binding<Bool>) -> some View {
        AppButton {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(isOn.wrappedValue ? 0.95 : 0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(color.opacity(isOn.wrappedValue ? 0 : 0.6), lineWidth: 1)
                    )
                    .frame(width: 12, height: 8)
                Text(label)
                    .font(.sans(13, weight: .medium))
            }
            .opacity(isOn.wrappedValue ? 1 : 0.55)
        }
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }
}

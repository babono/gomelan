//
//  VoiceMixer.swift
//  Kotek
//
//  The voice mixer allows listening to your half, your partner's half,
//  or muting either voice during practice.
//

import SwiftUI

/// One chip per voice; tapping it silences that voice — so a figure can be
/// learned by hearing it played first, then heard against the other half once
/// it is in the hands. It replaced a Voices dropdown on the waterfall, which
/// hid both voices behind a menu.
///
/// The glyph is a speaker in the voice's colour, slashed when silenced. It was
/// a colour swatch while the chips doubled as the score's legend, and a
/// speaker then read as a mute switch first and a legend second. The other
/// half no longer falls on the waterfall, so there it is no legend at all; on
/// the camera screen's score the speaker's colour still says whose voice.
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
                Image(systemName: isOn.wrappedValue ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.symbol(11, weight: .semibold))
                    .foregroundStyle(color.opacity(isOn.wrappedValue ? 0.95 : 0.6))
                    // As wide either way, so muting doesn't nudge the label.
                    .frame(width: 16)

                Text(label)
                    .font(.sans(11, weight: .medium))
                    .foregroundStyle(isOn.wrappedValue ? Theme.cream : Theme.inkStone.opacity(0.7))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(isOn.wrappedValue ? Theme.ink.opacity(0.55) : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.inkStone.opacity(0.35), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.appPlain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn.wrappedValue ? "On" : "Muted")
    }
}

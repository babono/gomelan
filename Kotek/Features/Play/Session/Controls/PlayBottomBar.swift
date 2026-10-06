//
//  PlayBottomBar.swift
//  Kotek
//
//  Bottom panel containing the session controls (half switch, tempo picker, voice mixer)
//  and the notes river score.
//

import SwiftUI

struct PlayBottomBar: View {
    @Bindable var app: AppState
    let engine: PlayEngine
    let keyRange: ClosedRange<Int>

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HalfSwitch(
                    chosenHalf: app.chosenHalf,
                    onSelect: { app.setHalf($0) }
                )
                .coachTarget(.half)

                TempoPicker(tempoScale: $app.tempoScale)
                    .coachTarget(.tempo)

                Spacer()

                VoiceMixer(
                    yourHalf: app.chosenHalf,
                    yourVoiceAudible: $app.yourVoiceAudible,
                    partnerAudible: $app.partnerAudible
                )
                .coachTarget(.voices)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(Theme.inkRaised.opacity(0.8))

            NotesRiver(
                engine: engine,
                keyRange: keyRange,
                keyCount: app.profile.keys.count,
                yourHalf: app.chosenHalf
            )
        }
    }
}

//
//  PracticeSectionView.swift
//  Kotek
//
//  Settings → Practice: how a session sounds and what it shows, for every
//  gangsa. Each of these can also be changed from the practice screen
//  without stopping; here is where they are found when not playing.
//

import SwiftUI

struct PracticeSectionView: View {
    @Bindable var app: AppState
    /// The waterfall's own switch reads this key when a session starts.
    @AppStorage("voiceCommands") private var voiceCommands = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(header: "While playing") {
                SettingsRow(
                    title: "Your half's voice",
                    subtitle: "Plays your half so you can copy it.",
                    divider: false
                ) {
                    Toggle("Your half's voice", isOn: $app.yourVoiceAudible).toggleStyle(.app).labelsHidden()
                }
                SettingsRow(title: "Partner's voice", subtitle: "Plays the other half, as a partner would.") {
                    Toggle("Partner's voice", isOn: $app.partnerAudible).toggleStyle(.app).labelsHidden()
                }
                SettingsRow(title: "Voice commands", subtitle: voiceHint) {
                    Toggle("Voice commands", isOn: $voiceCommands).toggleStyle(.app).labelsHidden()
                }
            }

            // Moved here from the gangsa card: it was always one setting for
            // the whole app, sitting in one gangsa's card.
            SettingsGroup(header: "Damping") {
                SettingsRow(
                    title: "Damping guide",
                    subtitle: "Shows when to damp each bilah: a falling hand marker and a thumb on the gangsa.",
                    divider: false
                ) {
                    AppMenuPicker(
                        options: DampGuide.allCases,
                        selection: $app.dampGuide,
                        title: \.title,
                        label: "Damping guide",
                        size: .compact
                    )
                    .fixedSize()
                }
            }
        }
    }

    /// The words to say, in the language voice commands listen in.
    private var voiceHint: LocalizedStringKey {
        VoiceCommand.Language.preferred == .indonesian
            ? "Say “pelan”, “cepat” or “jeda”."
            : "Say “slower”, “faster” or “pause”."
    }
}

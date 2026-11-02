//
//  AppMenuPicker.swift
//  Kotek
//
//  A capsule that opens a menu of choices: tempo, snap, sensor placement.
//

import SwiftUI

struct AppMenuPicker<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    /// What VoiceOver says before the value: "Tempo, 100%".
    let label: LocalizedStringResource
    var systemImage: String?
    var size = AppButtonSize.compact

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    if option == selection {
                        Label(title(option), systemImage: "checkmark")
                    } else {
                        Text(title(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.symbol(size.symbolPoints, weight: .semibold))
                }
                // As wide as the widest option.
                ZStack {
                    ForEach(options, id: \.self) { Text(title($0)).appLabel(size).hidden() }
                    Text(title(selection)).appLabel(size)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.symbol(size.symbolPoints - 4, weight: .semibold))
            }
            .foregroundStyle(Theme.cream)
            // The label is only the content and its padding — the tap area.
            .padding(.horizontal, size.horizontalPadding)
            .frame(minHeight: size.height)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // The pill OUTSIDE the menu. The system redraws a menu's label
        // itself while the menu opens and closes, and with the pill inside
        // it, the outline and the edge hanging below vanished for a frame
        // on every pick ("Solo" → "Co-op" flashed flat white). Out here it is
        // ours and never redrawn. No sink on press: a menu does not pass its
        // press to the label.
        .tactile(
            Capsule(),
            fill: Theme.glassTint,
            outline: Theme.hairline,
            base: Theme.hairline,
            depth: size.depth
        )
        .menuOrder(.fixed)
        .kajarOnChange(of: selection)
        .accessibilityLabel("\(String(localized: label)), \(title(selection))")
    }
}

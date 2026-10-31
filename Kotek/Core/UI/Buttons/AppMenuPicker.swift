//
//  AppMenuPicker.swift
//  Kotek
//
//  A glass capsule that opens a menu of choices: tempo, snap, sensor placement.
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
            .appControlSurface(size: size, shape: .capsule, prominence: .secondary, growsHitArea: false)
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
        .kajarOnChange(of: selection)
        .accessibilityLabel("\(String(localized: label)), \(title(selection))")
    }
}

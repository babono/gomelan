//
//  InstrumentNameField.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// Styled instrument name input field with focus and done handling.
struct InstrumentNameField: View {
    @Binding var name: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Call it")
                .font(.sans(13, weight: .medium))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Theme.stone)

            TextField("Gangsa", text: $name)
                .textFieldStyle(.plain)
                .font(.serif(24))
                .foregroundStyle(Theme.charcoal)
                .focused(isFocused)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: 340, alignment: .leading)
                .background(
                    Theme.deep.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: Theme.radius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius)
                        .strokeBorder(
                            isFocused.wrappedValue ? Theme.buttonFill : Theme.charcoal.opacity(0.15),
                            lineWidth: isFocused.wrappedValue ? 2 : 1
                        )
                )
                .onSubmit { isFocused.wrappedValue = false }
        }
    }
}

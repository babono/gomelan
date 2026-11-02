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
            SectionLabel("Name")

            TextField("Gangsa", text: $name)
                .textFieldStyle(.plain)
                // Body type, as the redesign draws a field; it was the
                // display face, which made the field read as a heading.
                .font(.sans(17))
                .foregroundStyle(Theme.cream)
                .focused(isFocused)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: 340, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius)
                        .strokeBorder(
                            isFocused.wrappedValue ? Theme.gold : Theme.hairline,
                            lineWidth: isFocused.wrappedValue ? 2 : 1
                        )
                )
                .onSubmit { isFocused.wrappedValue = false }
        }
    }
}

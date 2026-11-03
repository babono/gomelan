//
//  ResultsStat.swift
//  Kotek
//
//  One number on the results screen, in its own tile: "6 / cycles".
//

import SwiftUI

struct ResultsStat: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.serif(24))
                .foregroundStyle(Theme.heading)
            Text(label)
                .font(.sans(13))
                .foregroundStyle(Theme.description)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: 80)
        .background(Theme.surface, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline))
        .accessibilityElement(children: .combine)
    }
}

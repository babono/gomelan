//
//  AddInstrumentCardView.swift
//  Kotek
//
//  Narrow action card at the end of the profile rail to add a new gangsa.
//

import SwiftUI

struct AddInstrumentCardView: View {
    let onAdd: () -> Void

    var body: some View {
        Button {
            onAdd()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.symbol(22, weight: .semibold))
                Text("Add")
                    .font(.sans(15, weight: Theme.buttonWeight))
                    .textCase(.uppercase)
                    .tracking(Theme.buttonTracking)
            }
            .foregroundStyle(Theme.cream.opacity(0.85))
            .frame(width: 84, height: 240)
            .background(
                Theme.deep.opacity(0.35),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Theme.cream.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.kajar)
        .accessibilityLabel("Add a gangsa")
    }
}

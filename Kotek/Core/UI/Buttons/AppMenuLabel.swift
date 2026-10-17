//
//  AppMenuLabel.swift
//  Kotek
//
//  The face of a `Menu` that sits in a row of buttons: the tempo, the snap, the
//  sensor placement, which gangsa. Same capsule and type as `AppButton` —
//  it is a menu, but it has to read as one of the family.
//

import SwiftUI

struct AppMenuLabel: View {
    let title: String
    var systemImage: String?
    /// False when the menu has nothing to choose between.
    var showsChevron = true

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.symbol(16, weight: .semibold))
            }
            Text(title)
                .font(.sans(16, weight: .semibold))
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.symbol(11, weight: .semibold))
            }
        }
        .foregroundStyle(Theme.cream)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 20)
        .frame(minHeight: Theme.tapTarget)
        .controlSurface()
        .contentShape(Capsule())
    }
}

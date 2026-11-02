//
//  SensorTip.swift
//  Kotek
//
//  The popover that says no sensor is connected and what that costs, with
//  the way to connect one. Shared by the kotekan picker's sensor chip and
//  Kotek Studio's record button, so the two say it the same way.
//

import SwiftUI

struct SensorTip: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    /// nil leaves Connect out — Studio's, when connecting would leave the
    /// screen and lose the notes written so far.
    let onConnect: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.sans(17, weight: .semibold))
                .foregroundStyle(Theme.cream)
            Text(message)
                .font(.sans(14))
                .foregroundStyle(Theme.cream.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if let onConnect {
                    AppButton(title: "Connect", prominence: .primary, size: .compact) {
                        onDismiss()
                        onConnect()
                    }
                    AppButton(title: "Not now", size: .compact, action: onDismiss)
                } else {
                    AppButton(title: "Got it", size: .compact, action: onDismiss)
                }
            }
            .padding(.top, 6)
        }
        .padding(20)
        .frame(width: 320, alignment: .leading)
        .background(Theme.ground)
        .presentationCompactAdaptation(.popover)
    }
}

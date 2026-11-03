//
//  PolishCard.swift
//  Kotek
//
//  Kipli's explanation of one spot on "Where to polish": what happened, what
//  to try, and ‹ › to the next.
//

import SwiftUI

struct PolishCard: View {
    let spot: PolishSpot
    let index: Int
    let count: Int
    let onStep: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: spot.title)
                .font(.sans(18, weight: .semibold))
                .foregroundStyle(Theme.heading)
            Text(verbatim: spot.body)
                .font(.sans(14))
                .foregroundStyle(Theme.description)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(index + 1) of \(count)")
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.description)
                Spacer()
                AppIconButton(systemImage: "chevron.left", label: "Previous", size: .compact) { onStep(-1) }
                    .disabled(index == 0)
                AppIconButton(systemImage: "chevron.right", label: "Next", size: .compact) { onStep(1) }
                    .disabled(index == count - 1)
            }
        }
        .padding(16)
        .frame(width: 270, alignment: .leading)
        .background(Theme.deep, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline))
    }
}

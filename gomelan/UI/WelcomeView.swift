//
//  WelcomeView.swift
//  gomelan
//
//  Entry screen (PRD §8). Framing stays honest: this helps you take a first
//  step, before a teacher — never instead of one (§1).
//

import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            SectionLabel("Bali · Pemade · Kantilan")

            Text("Gomelan")
                .font(.serif(84, weight: .regular))
                .foregroundStyle(Theme.charcoal)

            Rectangle()
                .fill(Theme.charcoal.opacity(0.2))
                .frame(width: 260, height: 1)
                .padding(.vertical, 4)

            Text("a banjar that fits in your pocket")
                .font(.serif(22))
                .italic()
                .foregroundStyle(Theme.stone)

            Spacer().frame(height: 24)

            PillButton(title: "Go", style: .outlined) {
                app.begin()
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
    }
}

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
        HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Gomelan")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Play gamelan anywhere — no sekaa required.")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                Text("A guided first step at the gangsa. Mount your phone on a stand above the instrument, and Gomelan shows you which key to strike and when.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 16) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 90))
                    .foregroundStyle(Theme.accent.opacity(0.9))
                PrimaryButton(title: "Set up your instrument", systemImage: "camera.viewfinder") {
                    app.begin()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(48)
    }
}

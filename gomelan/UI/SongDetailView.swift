//
//  SongDetailView.swift
//  gomelan
//
//  Song detail + mode select (PRD §4 Flow B). Practice is the default for
//  first-time users — it serves the "fear of being wrong" barrier (§5.3).
//

import SwiftUI

struct SongDetailView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if let song = app.selectedSong {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    SecondaryButton(title: "Back", systemImage: "chevron.left") {
                        app.backToSongs()
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(song.title)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(song.difficulty.rawValue.capitalized) · \(song.bpm) BPM · \(song.notes.count) notes")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                }

                PatternStrip(song: song, keyCount: app.profile.keyCount)

                Spacer()

                HStack(spacing: 16) {
                    ModeCard(mode: .practice, recommended: true) { app.start(mode: .practice) }
                    ModeCard(mode: .play, recommended: false) { app.start(mode: .play) }
                }
            }
            .padding(40)
        } else {
            Color.clear.onAppear { app.backToSongs() }
        }
    }
}

/// A compact visualisation of the pattern (PRD §8 "pattern visualisation").
private struct PatternStrip: View {
    let song: Song
    let keyCount: Int

    var body: some View {
        GeometryReader { geo in
            let width: CGFloat = geo.size.width
            let height: CGFloat = geo.size.height
            let maxTime: CGFloat = CGFloat(max(song.durationMs, 1))
            let rowH: CGFloat = height / CGFloat(max(keyCount, 1))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.05))
                ForEach(song.notes) { note in
                    let x: CGFloat = width * CGFloat(note.timeMs) / maxTime
                    let y: CGFloat = rowH * CGFloat(keyCount - 1 - note.keyIndex)
                    let barWidth: CGFloat = max(6, width * CGFloat(note.durationMs) / maxTime)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.accent.opacity(0.85))
                        .frame(width: barWidth, height: max(6, rowH - 6))
                        .position(x: x + 6, y: y + rowH / 2)
                }
            }
        }
        .frame(height: 120)
    }
}

private struct ModeCard: View {
    let mode: PlayMode
    let recommended: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(mode.title).font(.title2.weight(.bold))
                    if recommended {
                        Text("Recommended")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.accent, in: Capsule())
                            .foregroundStyle(.black)
                    }
                }
                Text(mode.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(recommended ? Theme.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

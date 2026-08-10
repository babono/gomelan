//
//  SongListView.swift
//  gomelan
//
//  Song browse (PRD §4 Flow B, §8). Songs requiring more keys than the profile
//  has are greyed out and unselectable.
//

import SwiftUI

struct SongListView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Choose a pattern")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                SecondaryButton(title: "Settings", systemImage: "gearshape") {
                    app.openSettings()
                }
                RealignButton { app.realign() }
            }
            .padding(.bottom, 20)

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(app.songs) { song in
                        let playable = app.song(song, canPlayOn: app.profile)
                        SongRow(song: song, playable: playable)
                            .onTapGesture { if playable { app.select(song) } }
                    }
                }
            }
        }
        .padding(40)
    }
}

private struct SongRow: View {
    let song: Song
    let playable: Bool

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(song.difficulty.rawValue.capitalized) · \(song.bpm) BPM · \(song.requiredKeys) keys · \(song.durationMs / 1000)s")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            if playable {
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.5))
            } else {
                Label("Needs \(song.requiredKeys) keys", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(Theme.miss.opacity(0.9))
            }
        }
        .padding(20)
        .background(.white.opacity(playable ? 0.08 : 0.03), in: RoundedRectangle(cornerRadius: 14))
        .opacity(playable ? 1 : 0.5)
    }
}

//
//  TouchGangsa.swift
//  Kotek
//
//  The drawn gangsa under the piano roll, played with a finger like
//  GarageBand's keyboard: a bilah sounds on touch-down — not on lift, which
//  is a tap's whole length late — and while recording it is written the way
//  a sensor hit is. With no sensor to record from, each tap is written where
//  the line is and moves it on a step (`CreateKotekViewModel.step`).
//
//  Sized on its own, not by the play screen (`WaterfallPlayView`), which sinks
//  its gangsa off the glass and draws the tiles at their own ratio. Here the
//  strip is a fixed `shown` tall, ending at the safe area where a finger can
//  hit (the roll above keeps its height), and the tiles stretch to its bottom
//  (`GangsaLayout.stretches`). Their width is the lane a `laneHeight` gangsa
//  would have, capped by the screen width, so a 14-bilah gangsa is narrower.
//

import SwiftUI

struct TouchGangsa: View {
    let viewModel: CreateKotekViewModel

    /// The bar last struck and when, so it shows struck for a moment.
    @State private var struck: (key: Int, at: Date)?
    /// Down until the finger lifts: a drag that slides on is not a new stroke.
    @State private var down = false

    /// How long a tapped bar shows struck — the engine's flash length.
    private static let flash = 0.3
    /// Sets the lane (71pt), so the tile width, not the strip's length.
    private static let laneHeight: CGFloat = 185
    private static let shown: CGFloat = 120
    /// Room above for the end posts, which stand `postRise` over the tiles —
    /// under 20pt at the tallest lane (71pt).
    private static let postRoom: CGFloat = 20

    /// The whole strip, down to the safe area.
    static let visibleHeight = postRoom + shown

    var body: some View {
        GeometryReader { geo in
            let keys = viewModel.keyCount
            let layout = GangsaLayout(
                keyCount: keys,
                width: GangsaLayout.width(keyCount: keys, height: Self.laneHeight, fitting: geo.size.width - 40),
                stretches: true,
                // Past the safe area and the 4pt under the strip, to the glass.
                postBleed: 80
            )

            TimelineView(.animation(paused: struck == nil)) { timeline in
                GangsaView(layout: layout, cues: cues(at: timeline.date), tilted: false)
            }
            .frame(width: layout.frameWidth, height: Self.shown)
            .contentShape(Rectangle())
            // shortcut: one finger at a time (one DragGesture); per-bar
            // gestures if both mallets ever need to play at once.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !down else { return }
                        down = true
                        let key = Int((value.location.x - layout.framePad) / layout.lane)
                        strike(key.clamped(to: 0, keys - 1))
                    }
                    .onEnded { _ in down = false }
            )
            .accessibilityRepresentation {
                HStack {
                    ForEach(0 ..< keys, id: \.self) { key in
                        Button("Bilah \(key + 1)") { strike(key) }
                    }
                }
            }
            .padding(.top, Self.postRoom)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(height: Self.visibleHeight)
    }

    private func strike(_ key: Int) {
        viewModel.touch(key: key)
        let at = Date.now
        struck = (key, at)
        // Then let the timeline stop, unless another bar was struck since.
        Task {
            try? await Task.sleep(for: .seconds(Self.flash))
            if struck?.at == at { struck = nil }
        }
    }

    private func cues(at now: Date) -> [Int: BilahCue] {
        guard let struck, now.timeIntervalSince(struck.at) < Self.flash else { return [:] }
        return [struck.key: BilahCue(struckAge: now.timeIntervalSince(struck.at))]
    }
}

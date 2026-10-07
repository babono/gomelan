//
//  CountdownOverlay.swift
//  Kotek
//
//  Pre-roll count-in overlay over the camera feed.
//

import SwiftUI

/// What the screen says before the figure starts.
enum StartCue: Equatable {
    /// The count-in is running and the first stroke is more than three seconds
    /// off. The gong is already sounding, so this is a caption on something
    /// audible rather than a blank wait.
    case getReady
    case count(Int)
}

/// The pre-roll over the live feed (§4 Flow C).
struct CountdownOverlay: View {
    let cue: StartCue

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            switch cue {
            case .getReady:
                Text("Get ready…")
                    .font(.serif(44, weight: .regular))
                    .foregroundStyle(Theme.cream)
                    .transition(.opacity)
            case let .count(value):
                Text("\(value)")
                    .font(.serif(160, weight: .regular))
                    .foregroundStyle(Theme.cream)
                    .transition(.scale.combined(with: .opacity))
                    .id(value)
            }
        }
    }
}

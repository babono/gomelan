//
//  AppGuideView.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// Explainer content for "Your gangsa" (.app guide).
struct AppGuideView: View {
    var body: some View {
        GuideColumns {
            AppGuideInstrument()
        } right: {
            AppGuideProgress()
        }
    }
}

/// What the instrument on the other side of the camera is, and why it is the only one.
struct AppGuideInstrument: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideBlock(
                "The instrument",
                "Bronze bilah over bamboo resonators, struck with a panggul and damped with the other hand. Bronze rings for seconds, so damping matters as much as striking."
            )

            GuideBlock(
                "Only the gangsa",
                "Kotek reads one instrument. Reyong, jegogan, kendang and the rest of the gamelan are not supported yet."
            )

            GuideBlock(
                "Yours, specifically",
                "No two gamelan are tuned alike, so the app learns your instrument once — where its keys are, how a strike sounds — and keeps it. Each card here is one."
            )
        }
    }
}

/// What the app keeps from your playing.
struct AppGuideProgress: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideBlock(
                "Records",
                "Your best eight cycles in a row on a pattern is its record — one for each half and each speed, because playing sangsih at full tempo is not the same achievement as polos at half."
            )

            GuideBlock(
                "Notes landed",
                "Every stroke that finds the right bilah counts towards the total on this card, whichever half you were playing."
            )

            GuideBlock(
                "Where it slipped",
                "After a session, the results show how each stroke of the cycle went on average, so you can see which part of the pattern needs work."
            )
        }
    }
}

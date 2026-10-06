//
//  StrikeMeterView.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// Circular confidence ring and count of strikes learned.
/// Reads STRIKES rather than a percentage so the player has an actionable goal.
struct StrikeMeterView: View {
    let strikeCount: Int
    let strikesNeeded: Int
    let confidence: Double

    var body: some View {
        ZStack {
            Circle().stroke(Theme.copper.opacity(0.22), lineWidth: 5)
            Circle()
                .trim(from: 0, to: confidence)
                .stroke(Theme.copper, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: confidence)
            Text("\(min(strikeCount, strikesNeeded))/\(strikesNeeded)")
                .font(.serif(16))
                .foregroundStyle(Theme.cream)
                .contentTransition(.numericText())
        }
        .frame(width: 52, height: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(min(strikeCount, strikesNeeded)) of \(strikesNeeded) strikes learned")
    }
}

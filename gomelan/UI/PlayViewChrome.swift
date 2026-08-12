//
//  PlayViewChrome.swift
//  gomelan
//
//  Created by Rhea Aulia on 11/08/26.
//

import SwiftUI

struct PhaseBanner: View {
    let phase: SessionPhase

    var body: some View {
        Group {
            switch phase {
            case .countIn:
                label("Listen to the gong", Theme.gong)
            case .example:
                label("Watch and listen", Theme.upcoming)
            case .userTurn:
                label("Your turn", Theme.hit)
            }
        }
    }

    private func label(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(color.opacity(0.35), in: Capsule())
            .overlay(Capsule().stroke(color, lineWidth: 1.5))
            .id(text)
            .transition(.opacity)
    }
}

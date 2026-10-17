//
//  DetectionLogPanel.swift
//  Kotek
//
//  Horizontal recent strike history pills.
//

import SwiftUI

struct DetectionLogPanel: View {
    let log: [DetectionHit]

    var body: some View {
        if !log.isEmpty {
            HStack(spacing: 8) {
                ForEach(log) { hit in
                    HStack(spacing: 4) {
                        Text("\(hit.key)").fontWeight(.bold)
                        Image(systemName: hit.audioSnapped ? "waveform" : "eye")
                            .font(.symbol(9))
                    }
                    .font(.sans(13).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.5), in: Capsule())
                }
            }
            .padding(.bottom, 20)
        }
    }
}

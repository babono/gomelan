//
//  DetectionBannerView.swift
//  Kotek
//
//  Centre screen banner showing the latest detected strike and ear agreement.
//

import SwiftUI

struct DetectionBannerView: View {
    let hit: DetectionHit?

    var body: some View {
        VStack {
            Spacer()
            if let hit {
                VStack(spacing: 6) {
                    Text("KEY \(hit.key)")
                        .font(.system(size: 72, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    HStack(spacing: 8) {
                        Image(systemName: hit.audioSnapped ? "waveform.badge.checkmark" : "eye")
                        Text(hit.audioSnapped ? "vision + audio" : "vision only")
                        Text("· \(Int(hit.prob * 100))%")
                    }
                    .font(.subheadline.weight(.semibold).monospaced())
                    .foregroundStyle(hit.audioSnapped ? Theme.hit : .white.opacity(0.7))

                    if let heardKey = hit.heardKey {
                        HStack(spacing: 6) {
                            Image(systemName: hit.agrees == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                            Text("ear: \(heardKey)")
                            if let share = hit.heardShare {
                                Text("\(Int(share * 100))%")
                            }
                            if !hit.heardTrusted {
                                Text("· learning")
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(hit.agrees == true ? Theme.hit : Theme.wrong)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
                .id(hit.id)
                .transition(.scale.combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hit?.id)
    }
}

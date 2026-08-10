//
//  Components.swift
//  gomelan
//
//  Small shared UI pieces. Large, high-contrast, minimal — consistent with the
//  peripheral-legibility constraint (PRD §3.3).
//

import SwiftUI

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).fontWeight(.semibold)
            }
            .font(.title3)
            .foregroundStyle(.black)
            .padding(.vertical, 16)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
            .background(tint, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// A persistent "keys misaligned?" affordance (PRD §13.4).
struct RealignButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Keys misaligned?", systemImage: "viewfinder")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(.black.opacity(0.4), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

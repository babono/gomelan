//
//  AvatarView.swift
//  Kotek
//
//  The preset avatars a player picks from. Shared by the profile step and the
//  account card in Settings — and, later, a leaderboard.
//
//  Presets rather than uploads: nothing to store, resize or moderate, and the
//  artwork can carry the app's own world instead of a selfie. The images under
//  `Assets.xcassets/Avatars` are placeholders until the real set is drawn;
//  only the raw values are stored, so artwork can be swapped freely.
//

import SwiftUI

enum Avatar: String, CaseIterable, Identifiable {
    case wayang, barong, gangsa, kendang, gong, candi, jepun, canang, penjor, keris

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .wayang: "Wayang"
        case .barong: "Barong"
        case .gangsa: "Gangsa"
        case .kendang: "Kendang"
        case .gong: "Gong"
        case .candi: "Candi bentar"
        case .jepun: "Jepun"
        case .canang: "Canang sari"
        case .penjor: "Penjor"
        case .keris: "Keris"
        }
    }
}

struct AvatarView: View {
    let avatar: Avatar?
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let avatar {
                Image("Avatars/\(avatar.rawValue)")
                    .resizable()
                    .scaledToFit()
            } else {
                Circle()
                    .fill(Theme.cream.opacity(0.08))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.42))
                            .foregroundStyle(Theme.cream.opacity(0.5))
                    )
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(avatar?.title ?? String(localized: "No avatar"))
    }
}

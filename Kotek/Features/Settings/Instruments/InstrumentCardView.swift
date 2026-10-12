//
//  InstrumentCardView.swift
//  Kotek
//
//  A single instrument profile card on the Choose Instrument rail.
//

import SwiftUI

struct InstrumentCardView: View {
    let profile: InstrumentProfile
    let isCurrent: Bool
    let onSelect: () -> Void

    private static let width: CGFloat = 258
    private static let height: CGFloat = 240
    private static let photoHeight: CGFloat = 104

    var body: some View {
        Button {
            onSelect()
        } label: {
            let photo = InstrumentPhotoStore.image(for: profile)
            VStack(alignment: .leading, spacing: 0) {
                // Across the top, edge to edge, as the revamp draws it.
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: Self.width, height: Self.photoHeight)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.name)
                        .font(.serif(photo == nil ? 30 : 26))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("\(profile.keyCount) keys · \(lastPlayedText)")
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.description)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: photo == nil ? 12 : 4)

                    playedLine
                    statusDot
                }
                .padding(photo == nil ? 20 : 16)
            }
            .frame(width: Self.width, height: Self.height, alignment: .topLeading)
            .background(Theme.deep)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        isCurrent ? Theme.buttonFill : Theme.cream.opacity(0.10),
                        lineWidth: isCurrent ? 2 : 1
                    )
            )
        }
        .buttonStyle(.kajar)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Plays this gangsa")
    }

    private var playedLine: some View {
        let played = profile.hasBeenPlayed
        return Text(played ? "\(profile.notesLanded.formatted()) notes landed" : "Unplayed")
            .font(.sans(12, weight: .semibold))
            .textCase(.uppercase)
            .tracking(2)
            .foregroundStyle(played ? Theme.gold : Theme.cream.opacity(0.35))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var statusDot: some View {
        let learned = profile.hasLearnedBaseline
        return HStack(spacing: 8) {
            Circle()
                .strokeBorder(learned ? Color.clear : Theme.cream.opacity(0.45), lineWidth: 1.5)
                .background(Circle().fill(learned ? Theme.buttonFill : Color.clear))
                .frame(width: 8, height: 8)
            Text(learned ? "Voice learned" : "No voice yet")
                .font(.sans(13))
                .foregroundStyle(learned ? Theme.buttonFill : Theme.cream.opacity(0.45))
        }
    }

    private var lastPlayedText: String {
        guard let date = profile.lastPlayedDate else { return "new" }
        return date.formatted(.relative(presentation: .named))
    }

    private var accessibilityLabel: String {
        var parts = ["\(profile.name), \(profile.keyCount) keys"]
        parts.append(
            profile.hasBeenPlayed
                ? "last played \(lastPlayedText), \(profile.notesLanded) notes landed"
                : "not played yet"
        )
        parts.append(profile.hasLearnedBaseline ? "voice learned" : "no voice yet")
        return parts.joined(separator: ", ")
    }
}

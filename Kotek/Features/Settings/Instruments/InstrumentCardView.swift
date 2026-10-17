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

    /// The kotekan card's size (`KotekanCardView`), so the two pickers match.
    /// It was 258 x 240 with a 104pt photo, too tall for the carousel layout.
    static let width = KotekanCardView.cardWidth
    static let height = KotekanCardView.cardHeight
    private static let photoHeight: CGFloat = 62

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

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.serif(photo == nil ? 28 : 22))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("\(profile.keyCount) keys · \(lastPlayedText)")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.description)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 2)

                    // One line: two stacked ran out of card at this height.
                    HStack(spacing: 12) {
                        playedLine
                        statusDot
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, photo == nil ? 18 : 10)
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
        .accessibilityHint("Selects this gangsa")
    }

    private var playedLine: some View {
        let played = profile.hasBeenPlayed
        return Text(played ? "\(profile.notesLanded.formatted()) notes landed" : "Unplayed")
            .font(.sans(11, weight: .semibold))
            .textCase(.uppercase)
            .tracking(1.5)
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
                .font(.sans(12))
                .lineLimit(1)
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

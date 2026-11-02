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
    /// As tall as the rail allows, up to `maxHeight` — see there.
    var height: CGFloat = InstrumentCardView.maxHeight
    /// Centres a side card; on the centred one, goes on to its kotekan.
    let onSelect: () -> Void

    /// The kotekan card's width (`KotekanCardView`), so the two pickers line up.
    static let width = KotekanCardView.cardWidth
    /// Taller than the kotekan card, for the photo — the photo is how a player
    /// tells their gangsa apart, and at the kotekan card's 178 it was a strip.
    /// Not fixed: on a small phone in landscape the rail has less than this
    /// (it was once 240 and ran into the footer), so the card takes what the
    /// rail has, and the photo gives up the difference.
    /// The kotekan card's height, now the Next footer is gone; 240 crowded
    /// the search row.
    static let maxHeight = KotekanCardView.maxHeight
    /// Name, keys line and set-up marks, with their padding.
    private static let infoHeight: CGFloat = 90

    private var photoHeight: CGFloat {
        max(56, height - Self.infoHeight)
    }

    var body: some View {
        Button {
            onSelect()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Across the top, edge to edge, as the revamp draws it — and
                // on every card, so the names line up along the rail.
                photo
                    .frame(width: Self.width, height: photoHeight)
                    .clipped()

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.serif(22))
                        .foregroundStyle(Theme.heading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("\(profile.keyCount) bilah · \(lastPlayedText)")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.description)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 2)

                    // What this gangsa is set up with — the two things that
                    // change how it plays. "Notes landed" and the learned
                    // voice were here; the first is history, the second only
                    // matters to the camera mode.
                    HStack(spacing: 14) {
                        setupMark("Sound clips", done: hasSoundClips)
                        setupMark("Sensors", done: hasSensors)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: Self.width, height: height, alignment: .topLeading)
            // The design system's card: the gangsa on a wash of gold above
            // (Krem on a card that is not yours), the name on white below.
            // It was a charcoal band under a beige photo for one pass.
            .background(alignment: .top) {
                (isCurrent ? Theme.gold.mix(with: .white, by: 0.72) : Theme.deep)
                    .frame(height: photoHeight)
            }
            .opacity(isCurrent ? 1 : 0.55)
            .pickerCard(selected: isCurrent, tumpal: .large)
        }
        .buttonStyle(.appPlain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isCurrent ? "Opens this gangsa's kotekan" : "Selects this gangsa")
    }

    /// The gangsa's photo, or an image symbol where it has none — a plain
    /// placeholder, so a card without a photo still reads as "add one here".
    @ViewBuilder private var photo: some View {
        if let image = InstrumentPhotoStore.image(for: profile) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            // No photo: the gangsa itself, still, whole down to its feet,
            // with this one's bilah. As wide as the card allows, unless the
            // photo's band is too short for that — then as tall as it allows.
            let width = min(
                Self.width * 0.7,
                (photoHeight - 24) * Self.width / GangsaTable.height(for: Self.width, full: true)
            )
            GangsaTable(keyCount: profile.keyCount, animated: false, full: true)
                .frame(width: width, height: GangsaTable.height(for: width, full: true))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }

    /// At least one key recorded (`NoteClipCapture`).
    private var hasSoundClips: Bool {
        profile.keys.contains { $0.soundFile != nil }
    }

    /// A strike controller set up, so this gangsa can be scored.
    private var hasSensors: Bool {
        profile.controller != nil
    }

    /// A tick or an empty circle as well as the colour, so the state never
    /// rests on colour alone.
    private func setupMark(_ title: LocalizedStringKey, done: Bool) -> some View {
        Label {
            Text(title).font(.sans(12, weight: .medium))
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.symbol(12, weight: .semibold))
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(done ? Theme.cream : Theme.description.opacity(0.7))
        .lineLimit(1)
    }

    private var lastPlayedText: String {
        guard let date = profile.lastPlayedDate else { return String(localized: "new") }
        return date.formatted(.relative(presentation: .named))
    }

    private var accessibilityLabel: String {
        var parts = [String(localized: "\(profile.name), \(profile.keyCount) keys")]
        parts
            .append(profile
                .hasBeenPlayed ? String(localized: "last played \(lastPlayedText)") :
                String(localized: "not played yet"))
        parts.append(hasSoundClips ? String(localized: "has sound clips") : String(localized: "no sound clips"))
        parts.append(hasSensors ? String(localized: "sensors set up") : String(localized: "no sensors"))
        return parts.joined(separator: ", ")
    }
}

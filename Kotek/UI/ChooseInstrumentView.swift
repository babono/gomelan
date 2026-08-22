//
//  ChooseInstrumentView.swift
//  Kotek
//
//  Choose which saved gamelan to play. Profiles persist key alignments and
//  strike baselines across app launches and builds.
//
//  A rail of cards over the drifting pattern, with the add affordance as a
//  narrow card at the END of the row — so "which instrument" and "another
//  instrument" are the same gesture in the same place, and the rail scrolls as
//  one thing.
//
//  THE CARD IS THE WHOLE SCREEN. It used to carry a rename pencil, a delete
//  bin, a select button and a re-align button — five targets inside one card —
//  and then, after those moved to Settings, still needed a Next underneath it
//  to actually go anywhere. Tapping a card is not an ambiguous act: this screen
//  asks one question, so the card answers it and the app moves on. Everything
//  that manages an instrument (name, re-align, recalibrate, delete) lives in
//  Settings, which is per-instrument and reached from the kotekan screen.
//
//  A swipe-to-reveal edit/delete was considered and deliberately not built.
//  Nothing on screen can advertise it, so the actions become undiscoverable;
//  it collides with the horizontal scroll this rail already needs; and it would
//  put destructive actions one careless gesture from a card people tap
//  constantly. Settings asks for one more tap and is honest about where it is.
//
//  The rail is ordered most-recently-played first (`ProfileStore.byRecency`),
//  so the instrument you are sitting at is under your thumb. It re-sorts on
//  load, never while you are looking at it — a card that moves as you reach for
//  it is worse than one in the wrong place.
//

import SwiftUI

struct ChooseInstrumentView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Choose your gangsa",
                   onBack: { app.screen = .welcome },
                   trailingText: app.savedProfiles.isEmpty
                        ? nil : "\(app.savedProfiles.count) saved")

            if app.savedProfiles.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                rail
            }
        }
        // The active profile can be one that is not on the rail — a fresh
        // install starts on the bundled default, and deleting can leave the
        // selection pointing at nothing. Settings edits whatever is active, so
        // leaving it pointing at a card nobody can see is the one genuinely
        // confusing outcome here. Land on the first.
        .onAppear {
            guard let first = app.savedProfiles.first,
                  !app.savedProfiles.contains(where: { $0.id == app.profile.id })
            else { return }
            app.activateInstrument(first)
        }
    }

    // MARK: - The rail

    private var rail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(app.savedProfiles) { profile in
                    instrumentCard(profile)
                }
                addCard
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: .infinity)
    }

    private func instrumentCard(_ profile: InstrumentProfile) -> some View {
        // Outlined means CURRENT, not "selected" — nothing is staged any more.
        // It is the instrument Settings will edit and the one you were last
        // playing, which is worth being able to spot on a rail of four.
        let isCurrent = app.profile.id == profile.id

        return Button {
            app.selectInstrument(profile)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.name)
                    .font(.serif(30))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Keys and recency on one line: two short facts that would each
                // waste a row of a card this size, and together they say what
                // the instrument is and when you last touched it.
                Text("\(profile.keyCount) keys · \(lastPlayedText(profile))")
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.cream.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 12)

                grade(profile)

                // A filled dot for a learned voice, a hollow one for not — the
                // design's own vocabulary, and readable without colour vision.
                // Kept because it is the only thing on the card that changes
                // what happens when you play.
                statusDot(profile)
            }
            .frame(width: 218, height: 200, alignment: .topLeading)
            .padding(20)
            // Selection reads by BORDER, not fill: a filled card competes with
            // the pattern behind it, and on a rail the eye finds an outline
            // faster than a shade.
            .background(Theme.deep.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(isCurrent ? Theme.buttonFill : Theme.cream.opacity(0.10),
                                  lineWidth: isCurrent ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(profile))
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Plays this gangsa")
    }

    /// The grade: the rung this instrument has reached, and how far into it.
    ///
    /// Named, not numbered, and glossed in English — see `Mastery`. The count of
    /// notes behind it stays in Settings; nobody wants to read a number on a
    /// card, but "how close is the next one" reads at a glance from a rail.
    private func grade(_ profile: InstrumentProfile) -> some View {
        let mastery = profile.mastery
        let played = profile.hasBeenPlayed

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(played ? mastery.rank.title : "Unplayed")
                    .font(.sans(12, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(played ? Theme.gold : Theme.cream.opacity(0.35))
                    .fixedSize()

                if played {
                    Text(mastery.rank.gloss)
                        .font(.sans(12))
                        .foregroundStyle(Theme.cream.opacity(0.38))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.cream.opacity(0.12))
                    if played {
                        Capsule()
                            .fill(Theme.gold)
                            // A floor of 3pt so a freshly-played instrument
                            // shows something. A bar at literally zero width is
                            // indistinguishable from a broken one.
                            .frame(width: max(3, geo.size.width * mastery.progress))
                    }
                }
            }
            .frame(height: 3)
        }
    }

    /// The add affordance, sized and shaped as a card so the rail reads as one
    /// row of choices — narrower, because it is an action rather than a thing.
    private var addCard: some View {
        Button {
            app.addNewInstrument()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.symbol(22, weight: .semibold))
                Text("Add")
                    .font(.sans(15, weight: Theme.buttonWeight))
                    .textCase(.uppercase)
                    .tracking(Theme.buttonTracking)
            }
            .foregroundStyle(Theme.cream.opacity(0.85))
            .frame(width: 84, height: 240)
            .background(Theme.deep.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Theme.cream.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a gangsa")
    }

    private func statusDot(_ profile: InstrumentProfile) -> some View {
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

    // MARK: - Text

    /// "2 hours ago", "yesterday", or "new". Relative rather than a date,
    /// because the only thing anyone reads this for is which instrument they
    /// were just at.
    private func lastPlayedText(_ profile: InstrumentProfile) -> String {
        guard let date = profile.lastPlayedDate else { return "new" }
        return date.formatted(.relative(presentation: .named))
    }

    /// Spoken as one sentence. VoiceOver reading a card as five separate
    /// fragments — name, keys, recency, rank, gloss, voice — is how a rail of
    /// four instruments becomes twenty-four stops.
    private func accessibilityLabel(_ profile: InstrumentProfile) -> String {
        var parts = ["\(profile.name), \(profile.keyCount) keys"]
        parts.append(profile.hasBeenPlayed
                     ? "last played \(lastPlayedText(profile)), \(profile.mastery.rank.title)"
                     : "not played yet")
        parts.append(profile.hasLearnedBaseline ? "voice learned" : "no voice yet")
        return parts.joined(separator: ", ")
    }

    /// Centred on the empty rail. Deliberately short: this sits in the space a
    /// row of cards occupies, which on a landscape phone is not tall.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tuningfork")
                .font(.symbol(32))
                .foregroundStyle(Theme.buttonFill)

            Text("No gangsa yet")
                .font(.serif(30))
                .foregroundStyle(Theme.cream)

            Text("Every gamelan is tuned differently, so Gomelan learns your gangsa — where the keys are and how they sound.")
                .font(.sans(15))
                .foregroundStyle(Theme.cream.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 440)

            PillButton(title: "Set up · 4 steps", style: .filled) {
                app.addNewInstrument()
            }
            .padding(.top, 4)
        }
        .padding(24)
    }
}

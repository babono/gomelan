//
//  ChooseInstrumentView.swift
//  Kotek
//
//  Choose which saved gamelan to play. Profiles persist key alignments and
//  strike baselines across app launches and builds.
//
//  A rail of cards over the drifting pattern, the selected one outlined, with
//  the add affordance as a narrow card at the END of the row — so "which
//  instrument" and "another instrument" are the same gesture in the same place,
//  and the rail scrolls as one thing.
//
//  THE CARD IS THE CONTROL. It used to carry a rename pencil, a delete bin, a
//  select button and a re-align button — five targets inside one card, on a
//  screen whose only question is "which one". Managing an instrument is a
//  different job from picking one, and it now lives in Settings, reached from
//  the kotekan screen. What is left here is a card you tap and a footer that
//  confirms, which is the whole decision.
//
//  A swipe-to-reveal edit/delete was considered and deliberately not built.
//  Nothing on screen can advertise it, so the actions become undiscoverable;
//  it collides with the horizontal scroll this rail already needs; and it would
//  put destructive actions one careless gesture from a card people tap
//  constantly. Settings asks for one more tap and is honest about where it is.
//

import SwiftUI

struct ChooseInstrumentView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Choose your instrument",
                   onBack: { app.screen = .welcome })

            // Both states keep the same frame — bar, one flexible middle,
            // footer — so only the middle changes and the footer cannot be
            // pushed off the bottom.
            if app.savedProfiles.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                rail
            }

            if !app.savedProfiles.isEmpty { footer }
        }
        // The active profile can be one that is not on the rail — a fresh
        // install starts on the bundled default, and deleting can leave the
        // selection pointing at nothing. Confirming a card nobody can see is
        // the one genuinely confusing outcome here, so land on the first.
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
        let isSelected = app.profile.id == profile.id

        return Button {
            app.activateInstrument(profile)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.name)
                    .font(.serif(30))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)

                Text("\(profile.keyCount) Keys")
                    .font(.sans(17, weight: .medium))
                    .foregroundStyle(Theme.cream.opacity(0.62))

                Spacer(minLength: 12)

                // A filled dot for a learned voice, a hollow one for not — the
                // design's own vocabulary, and readable without colour vision.
                // The only status left on the card, because it is the only thing
                // here that changes what happens when you play.
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
                    .strokeBorder(isSelected ? Theme.buttonFill : Theme.cream.opacity(0.10),
                                  lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Selects this instrument")
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
        .accessibilityLabel("Add an instrument")
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

    // MARK: - Chrome

    /// Confirm and a shortcut, with the saved count as quiet context.
    ///
    /// No rule above it. The rail already ends in space, and a hairline across a
    /// screen this soft draws a boundary the layout has made anyway.
    private var footer: some View {
        HStack(spacing: 14) {
            PillButton(title: "Next", style: .filled, compact: true) {
                app.selectInstrument(app.profile)
            }

            PillButton(title: "Recalibrate", style: .outlined, compact: true) {
                app.realignInstrument(app.profile)
            }

            Spacer()

            Text("\(app.savedProfiles.count) saved")
                .font(.sans(14))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Theme.cream.opacity(0.45))
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
        .padding(.top, 4)
    }

    /// Centred on the empty rail. Deliberately short: this sits in the space a
    /// row of cards occupies, which on a landscape phone is not tall.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tuningfork")
                .font(.symbol(32))
                .foregroundStyle(Theme.buttonFill)

            Text("No instruments yet")
                .font(.serif(30))
                .foregroundStyle(Theme.cream)

            Text("Every gamelan is tuned differently, so Kotek learns yours — where the keys are and how they sound.")
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

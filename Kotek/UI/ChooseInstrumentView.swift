//
//  ChooseInstrumentView.swift
//  Kotek
//
//  Choose or manage saved gamelan instrument profiles. Persists key alignments
//  and strike baselines across app launches and builds.
//
//  Built to the Kotek design: a rail of tall cards over the drifting pattern,
//  the selected one outlined in cream and the rest in held-back gold, with the
//  add affordance as a narrow card at the end of the row rather than a button
//  somewhere else — so "which instrument" and "another instrument" are the same
//  gesture in the same place.
//

import SwiftUI

struct ChooseInstrumentView: View {
    @Environment(AppState.self) private var app

    @State private var editingProfileId: String? = nil
    @State private var editingNameText: String = ""

    @State private var profileToDelete: InstrumentProfile?
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Choose your instrument",
                   backTitle: "Home",
                   onBack: { app.screen = .welcome })

            //R The empty message is plain centred text, not a card: a card here
            //R read as an instrument you could not use. Both states keep the same
            //R frame — top bar, one flexible middle, footer — so only the middle
            //R changes, and the footer cannot be pushed off the bottom.
            if app.savedProfiles.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(app.savedProfiles) { profile in
                            instrumentCard(profile)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                .frame(maxHeight: .infinity)
            }

            if editingProfileId == nil {
                footer
            }
        }
        .animation(.spring(duration: 0.25), value: editingProfileId)
        .confirmationDialog("Delete Instrument?",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible,
                            presenting: profileToDelete) { profile in
            Button("Delete \(profile.name)", role: .destructive) {
                app.deleteInstrument(profile.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { profile in
            Text("Are you sure you want to delete '\(profile.name)'? This cannot be undone.")
        }
    }

    /// Centred on the empty rail. Deliberately short: this sits in the same
    /// space a row of cards occupies, which on a landscape phone is not tall.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tuningfork")
                .font(.sans(32))
                .foregroundStyle(Theme.gold)

            Text("No instruments yet")
                .font(.serif(30))
                .foregroundStyle(Theme.charcoal)

            Text("Every gamelan is tuned differently, so Kotek learns yours — where the bilah are and how they sound.")
                .font(.sans(14))
                .foregroundStyle(Theme.stone)
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

    private func instrumentCard(_ profile: InstrumentProfile) -> some View {
        let isSelected = app.profile.id == profile.id
        let isEditing = editingProfileId == profile.id

        return VStack(alignment: .leading, spacing: 14) {
            // Card Header: Name (or Inline Textfield) + Actions
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if isEditing {
                        HStack(spacing: 6) {
                            TextField("Instrument Name", text: $editingNameText)
                                .font(.serif(18))
                                .foregroundStyle(Theme.cream)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.ground, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.gold, lineWidth: 1.5))
                                .onSubmit { saveInlineRename(profile) }

                            Button {
                                saveInlineRename(profile)
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.sans(20))
                                    .foregroundStyle(Theme.terracotta)
                            }
                            .buttonStyle(.plain)

                            Button {
                                editingProfileId = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.sans(18))
                                    .foregroundStyle(Theme.stone.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Text(profile.name)
                                .font(.serif(27))
                                .foregroundStyle(isSelected ? Theme.cream : Theme.cream.opacity(0.74))
                                .lineLimit(1)

                            Button {
                                editingProfileId = profile.id
                                editingNameText = profile.name
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.sans(12, weight: .semibold))
                                    .foregroundStyle(Theme.terracotta)
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("\(profile.keyCount) BILAH")
                        .font(.sans(12))
                        .tracking(1.9)
                        .foregroundStyle(Theme.gold)
                }

                if !isEditing {
                    Spacer()

                    Button {
                        profileToDelete = profile
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.sans(13))
                            .foregroundStyle(Theme.stone.opacity(0.7))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 8)

            // A filled dot for a learned voice, a hollow one for not — the
            // design's own vocabulary, and readable without colour vision.
            statusDot(title: profile.hasLearnedBaseline ? "VOICE LEARNED" : "NO VOICE YET",
                      filled: profile.hasLearnedBaseline)

            // Action Buttons
            HStack(spacing: 10) {
                PillButton(title: isSelected ? "Active" : "Select & Play",
                           style: isSelected ? .filled : .outlined,
                           compact: true) {
                    app.selectInstrument(profile)
                }

                PillButton(title: "Re-align", style: .outlined, compact: true) {
                    app.realignInstrument(profile)
                }
            }
        }
        .padding(20)
        .frame(width: isEditing ? 310 : 250, height: isEditing ? 220 : 236)
        // Selected reads by BORDER, not fill: a filled card competes with the
        // pattern behind it, and on a rail the eye finds an outline faster.
        .background(Theme.deep.opacity(isSelected ? 0.82 : 0.78),
                    in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(isSelected ? Theme.cream : Theme.gold.opacity(0.38),
                              lineWidth: isSelected ? 2 : 1)
        )
    }

    private func statusDot(title: String, filled: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .strokeBorder(filled ? Color.clear : Theme.cream, lineWidth: 2)
                .background(Circle().fill(filled ? Theme.bronze : Color.clear))
                .frame(width: 8, height: 8)
            Text(title)
                .font(.sans(12))
                .tracking(1.7)
                .foregroundStyle(filled ? Theme.bronze : Theme.cream)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            PillButton(title: "+ Add Instrument", style: .filled, compact: true) {
                app.addNewInstrument()
            }

            Spacer()

            Text(app.savedProfiles.isEmpty
                 ? "NONE SAVED"
                 : "\(app.savedProfiles.count) SAVED")
                .font(.sans(13))
                .tracking(1.8)
                .foregroundStyle(Theme.gold.opacity(0.75))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.gold.opacity(0.2)).frame(height: 1)
        }
    }

    private func saveInlineRename(_ profile: InstrumentProfile) {
        let trimmed = editingNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            editingProfileId = nil
            return
        }
        var updated = profile
        updated.name = trimmed
        if app.profile.id == updated.id {
            app.profile = updated
        }
        //R Save the instrument that was RENAMED. `saveProfile()` writes
        //R `app.profile`, so renaming any instrument other than the active one
        //R was silently discarded — and worse, re-wrote the active one.
        app.saveInstrument(updated)
        editingProfileId = nil
    }
}

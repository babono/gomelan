//
//  ChooseInstrumentView.swift
//  gomelan
//
//  Choose or manage saved gamelan instrument profiles. Persists key alignments
//  and strike baselines across app launches and builds. Styled consistently with
//  ChooseKotekanView on warm cream paper.
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
        .background(Theme.cream)
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
                .foregroundStyle(Theme.terracotta)

            Text("No instruments yet")
                .font(.serif(26, weight: .bold))
                .foregroundStyle(Theme.charcoal)

            Text("Every gamelan is tuned differently, so gomelan learns yours — where the bilah are and how they sound.")
                .font(.sans(14))
                .foregroundStyle(Theme.stone)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 440)

            PillButton(title: "Set up · 4 steps", style: .filled, tint: Theme.terracotta) {
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
                                .font(.serif(16, weight: .bold))
                                .foregroundStyle(Theme.charcoal)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.terracotta, lineWidth: 1.5))
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
                                .font(.serif(22, weight: .bold))
                                .foregroundStyle(Theme.charcoal)
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

                    Text("\(profile.keyCount) bilah keys")
                        .font(.sans(13))
                        .foregroundStyle(Theme.stone)
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

            // Badges
            VStack(alignment: .leading, spacing: 6) {
                badge(title: "Aligned", systemImage: "rectangle.and.arrow.up.right.and.arrow.down.left", active: true)
                badge(title: profile.hasLearnedBaseline ? "Voice Learned" : "No Voice Baseline",
                      systemImage: profile.hasLearnedBaseline ? "checkmark.seal.fill" : "waveform.slash",
                      active: profile.hasLearnedBaseline)
            }

            Spacer(minLength: 12)

            Divider().background(Theme.charcoal.opacity(0.12))

            // Action Buttons
            HStack(spacing: 10) {
                PillButton(title: isSelected ? "Active" : "Select & Play",
                           style: isSelected ? .filled : .outlined,
                           tint: Theme.terracotta,
                           compact: true) {
                    app.selectInstrument(profile)
                }

                PillButton(title: "Re-align", style: .outlined, tint: Theme.stone, compact: true) {
                    app.realignInstrument(profile)
                }
            }
        }
        .padding(18)
        .frame(width: isEditing ? 310 : 260, height: isEditing ? 220 : 250)
        .background(isSelected ? Theme.creamSunken : Color.white.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isSelected ? Theme.terracotta : Theme.charcoal.opacity(0.15),
                              lineWidth: isSelected ? 2 : 1)
        )
    }

    private func badge(title: String, systemImage: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.sans(10, weight: .semibold))
            Text(title)
                .font(.sans(11, weight: .medium))
        }
        .foregroundStyle(active ? Theme.terracotta : Theme.stone)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(active ? Theme.terracotta.opacity(0.12) : Theme.charcoal.opacity(0.05), in: Capsule())
    }

    private var footer: some View {
        HStack(spacing: 16) {
            PillButton(title: "+ Add Instrument", style: .filled, tint: Theme.terracotta, compact: true) {
                app.addNewInstrument()
            }

            Spacer()

            Text(app.savedProfiles.isEmpty
                 ? "No instruments saved"
                 : "\(app.savedProfiles.count) saved instrument\(app.savedProfiles.count == 1 ? "" : "s")")
                .font(.sans(13))
                .foregroundStyle(Theme.stone)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Theme.creamSunken.opacity(0.6))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.charcoal.opacity(0.1)).frame(height: 1)
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

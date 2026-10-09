//
//  InstrumentSectionView.swift
//  Kotek
//
//  Settings card for renaming, recalibrating, and deleting the active gangsa.
//

import SwiftUI

struct InstrumentSectionView: View {
    @Bindable var viewModel: SettingsViewModel
    @FocusState private var nameFocused: Bool

    private var app: AppState {
        viewModel.app
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Theme.cream.opacity(0.62))

                TextField("Gangsa name", text: $viewModel.draftName)
                    .textFieldStyle(.plain)
                    .font(.serif(22))
                    .foregroundStyle(Theme.cream)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 360, alignment: .leading)
                    .background(Theme.deep.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.radius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radius)
                            .strokeBorder(
                                nameFocused ? Theme.buttonFill : Theme.cream.opacity(0.15),
                                lineWidth: nameFocused ? 2 : 1
                            )
                    )
                    .onSubmit { viewModel.commitName() }
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { viewModel.commitName() }
                    }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(
                    "\(app.profile.keyCount) keys · \(app.profile.calibratedKeyCount) tuned · \(app.profile.hasLearnedBaseline ? "voice learned" : "no voice yet")"
                )
                .font(.sans(14))
                .foregroundStyle(Theme.cream.opacity(0.62))

                Text(gradeLine)
                    .font(.sans(14))
                    .foregroundStyle(Theme.cream.opacity(0.62))
            }

            FlowLayout(spacing: 10) {
                SecondaryButton(title: "Re-align keys", systemImage: "viewfinder") {
                    app.realign()
                }
                SecondaryButton(title: "Calibrate voice", systemImage: "waveform") {
                    app.openCalibration()
                }
                SecondaryButton(title: "Switch gangsa", systemImage: "arrow.triangle.2.circlepath") {
                    app.openChooseInstrument()
                }
            }

            Button(role: .destructive) {
                viewModel.showDeleteConfirm = true
            } label: {
                Label("Delete this gangsa", systemImage: "trash")
                    .font(.sans(15, weight: Theme.buttonWeight))
                    .tracking(Theme.buttonTracking)
                    .foregroundStyle(Theme.miss)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radius)
                            .strokeBorder(Theme.miss.opacity(0.5), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
            }
            .buttonStyle(.kajar)
            .padding(.top, 4)
        }
    }

    private var gradeLine: String {
        let p = app.profile
        guard p.hasBeenPlayed else {
            return "Unplayed · the grade starts on your first scored session"
        }
        let m = p.mastery
        var line = "\(m.rank.title) — \(m.rank.gloss) · \(m.notes.formatted()) notes landed"
        if let next = m.next, let togo = m.notesToNext {
            line += " · \(togo.formatted()) to \(next.title)"
        }
        if let played = p.lastPlayedDate {
            line += " · played \(played.formatted(.relative(presentation: .named)))"
        }
        return line
    }
}

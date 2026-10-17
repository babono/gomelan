//
//  InstrumentSectionView.swift
//  Kotek
//
//  Settings card for renaming, recalibrating, and deleting the active gangsa.
//
//  The strike controller and the note clips come first: this version plays on
//  the waterfall, hears strikes from the sensors and sounds your own recorded
//  bilah. Re-align keys and Calibrate voice only serve the camera mode, so
//  they moved to Deprecated.
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
            HStack(alignment: .bottom, spacing: 16) {
                GangsaPhotoPicker(
                    image: InstrumentPhotoStore.image(for: app.profile),
                    onPick: { app.setPhoto($0, for: app.profile.id) },
                    width: 120, height: 76
                )
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
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("\(app.profile.keyCount) keys · \(recordedClips) of \(app.profile.keyCount) note clips")
                    .font(.sans(14))
                    .foregroundStyle(Theme.cream.opacity(0.62))

                Text(playedLine)
                    .font(.sans(14))
                    .foregroundStyle(Theme.cream.opacity(0.62))
            }

            controller

            noteClips

            FlowLayout(spacing: 10) {
                AppButton("Switch gangsa", systemImage: "arrow.triangle.2.circlepath") {
                    app.openChooseInstrument()
                }
                AppButton("History", systemImage: "clock.arrow.circlepath") {
                    app.openHistory()
                }
            }

            AppButton("Delete this gangsa", systemImage: "trash", prominence: .destructive) {
                viewModel.showDeleteConfirm = true
            }
            .padding(.top, 4)
        }
    }

    /// The strike controller (§3.6) — this gangsa's only. Others sharing it
    /// keep their own setup whatever happens here.
    private var controller: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Strike controller")
            if let link = app.profile.controller {
                Text(controllerLine(link))
                    .font(.sans(14))
                    .foregroundStyle(Theme.cream.opacity(0.62))
                ControllerStatusChip()
                FlowLayout(spacing: 10) {
                    AppButton("Check keys", systemImage: "checklist") {
                        app.openControllerSetup(recheck: true)
                    }
                    AppButton("Change controller", systemImage: "arrow.left.arrow.right") {
                        app.openControllerSetup()
                    }
                    AppButton("Forget controller", systemImage: "xmark.circle") {
                        app.forgetController()
                    }
                }
            } else {
                Text(
                    "Optional. Piezo sensors on the bilah feel exactly which key you hit and when — no camera or microphone needed."
                )
                .font(.sans(14))
                .foregroundStyle(Theme.cream.opacity(0.62))
                .frame(maxWidth: 520, alignment: .leading)
                AppButton("Connect controller", systemImage: "dot.radiowaves.left.and.right") {
                    app.openControllerSetup()
                }
            }
        }
    }

    /// This gangsa's own recorded bilah (`NoteClipCapture`). A key without a
    /// clip plays the bundled sample, so this is optional too.
    private var noteClips: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Note clips")
            Text("Record each bilah so the guide and partner sound like your gangsa.")
                .font(.sans(14))
                .foregroundStyle(Theme.cream.opacity(0.62))
                .frame(maxWidth: 520, alignment: .leading)
            AppButton("Capture note clips", systemImage: "waveform.badge.mic") {
                app.openNoteCapture()
            }
        }
    }

    private var recordedClips: Int {
        app.profile.keys.filter { $0.soundFile != nil }.count
    }

    private func controllerLine(_ link: ControllerLink) -> String {
        let sensors = app.profile.keys.filter { $0.sensorInput != nil }.count
        var line = "\(link.name) · sensors on \(sensors) of \(app.profile.keyCount) keys"
        if sensors < app.profile.keyCount { line += " · the rest use camera + mic" }
        return line
    }

    private var playedLine: String {
        let p = app.profile
        guard p.hasBeenPlayed else { return "Unplayed" }
        var line = "\(p.notesLanded.formatted()) notes landed in \(p.sessionsPlayed.formatted()) sessions"
        if let played = p.lastPlayedDate {
            line += " · played \(played.formatted(.relative(presentation: .named)))"
        }
        return line
    }
}

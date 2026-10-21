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

            damping

            FlowLayout(spacing: 10) {
                AppButton(title: "Switch gangsa", systemImage: "arrow.triangle.2.circlepath", size: .compact) {
                    app.openChooseInstrument()
                }
                AppButton(title: "History", systemImage: "clock.arrow.circlepath", size: .compact) {
                    app.openHistory()
                }
            }

            AppButton(
                title: "Delete this gangsa",
                systemImage: "trash",
                size: .compact,
                tint: Theme.miss,
                role: .destructive
            ) {
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
                    AppButton(title: "Check keys", systemImage: "checklist", size: .compact) {
                        app.openControllerSetup(recheck: true)
                    }
                    AppButton(title: "Change controller", systemImage: "arrow.left.arrow.right", size: .compact) {
                        app.openControllerSetup()
                    }
                    AppButton(title: "Forget controller", systemImage: "xmark.circle", size: .compact) {
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
                AppButton(title: "Connect controller", systemImage: "dot.radiowaves.left.and.right", size: .compact) {
                    app.openControllerSetup()
                }
            }
        }
    }

    /// This gangsa's own recorded bilah (`NoteClipCapture`). A key without a
    /// clip plays the bundled sample, so this is optional too.
    ///
    /// Once there is a recording, a choice of which to hear. Before, there is
    /// nothing to choose between, so no picker.
    private var noteClips: some View {
        @Bindable var bindableApp = app
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Note clips")
            Text("Record each bilah so the guide and partner sound like your gangsa.")
                .font(.sans(14))
                .foregroundStyle(Theme.cream.opacity(0.62))
                .frame(maxWidth: 520, alignment: .leading)
            if recordedClips > 0 {
                Picker("Key sounds", selection: $bindableApp.playsRecordedSounds) {
                    Text("Default").tag(false)
                    Text("Recorded").tag(true)
                }
                .pickerStyle(.segmented)
                .kajarOnChange(of: app.playsRecordedSounds)
                .frame(maxWidth: 280)
                .accessibilityLabel("Key sounds")
                if app.playsRecordedSounds, recordedClips < app.profile.keyCount {
                    Text("Keys you haven't recorded play the default sound.")
                        .font(.sans(13))
                        .foregroundStyle(Theme.cream.opacity(0.62))
                }
            }
            AppButton(title: "Capture note clips", systemImage: "waveform.badge.mic", size: .compact) {
                app.openNoteCapture()
            }
        }
    }

    /// Read when a practice starts, so a change here applies from the next one.
    private var damping: some View {
        @Bindable var bindableApp = app
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Damping")
            Toggle("Show damping", isOn: $bindableApp.showsDamp)
                .tint(Theme.terracotta)
                .frame(maxWidth: 360)
                .foregroundStyle(Theme.cream)
            Text("A hand on each bilah as its note ends, on the waterfall and the gangsa.")
                .font(.sans(14))
                .foregroundStyle(Theme.cream.opacity(0.62))
                .frame(maxWidth: 520, alignment: .leading)
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

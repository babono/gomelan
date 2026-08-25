//
//  SettingsView.swift
//  Kotek
//
//  Settings (PRD §8): recalibrate, tempo, audio cues, detection, and the dev
//  test screens.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app

    /// The name being typed, held locally so the profile is written once on
    /// commit rather than on every keystroke — each write hits disk and reloads
    /// the whole list.
    @State private var draftName: String = ""
    @State private var showDeleteConfirm = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            TopBar(title: "Settings",
                   backTitle: "Done",
                   onBack: { app.closeSettings() })

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    section(app.profile.name) {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Name")
                                    .font(.sans(13, weight: .medium))
                                    .foregroundStyle(Theme.cream.opacity(0.55))

                                TextField("Gangsa name", text: $draftName)
                                    .textFieldStyle(.plain)
                                    .font(.serif(22))
                                    .foregroundStyle(Theme.cream)
                                    .focused($nameFocused)
                                    .submitLabel(.done)
                                    .autocorrectionDisabled()
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: 360, alignment: .leading)
                                    .background(Theme.deep.opacity(0.6),
                                                in: RoundedRectangle(cornerRadius: Theme.radius))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.radius)
                                            .strokeBorder(nameFocused ? Theme.buttonFill
                                                                      : Theme.cream.opacity(0.15),
                                                          lineWidth: nameFocused ? 2 : 1)
                                    )
                                    // Committed on Return AND on losing focus,
                                    // so a name typed and then navigated away
                                    // from is not silently thrown away.
                                    .onSubmit { commitName() }
                                    .onChange(of: nameFocused) { _, focused in
                                        if !focused { commitName() }
                                    }
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(app.profile.keyCount) keys · \(app.profile.calibratedKeyCount) tuned · \(app.profile.hasLearnedBaseline ? "voice learned" : "no voice yet")")
                                    .font(.sans(14))
                                    .foregroundStyle(Theme.cream.opacity(0.62))

                                // The numbers behind the card's grade. They live
                                // here rather than on the card because a rail is
                                // read at a glance and a count of notes is not;
                                // but "how much further" is a fair question and
                                // this is the screen that owes an answer.
                                Text(gradeLine)
                                    .font(.sans(14))
                                    .foregroundStyle(Theme.cream.opacity(0.62))
                            }

                            FlowLayout(spacing: 10) {
                                SecondaryButton(title: "Re-align keys", systemImage: "viewfinder") { app.realign() }
                                SecondaryButton(title: "Calibrate voice", systemImage: "waveform") { app.openCalibration() }
                                SecondaryButton(title: "Switch gangsa", systemImage: "arrow.triangle.2.circlepath") { app.openChooseInstrument() }
                            }

                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete this gangsa", systemImage: "trash")
                                    .font(.sans(15, weight: Theme.buttonWeight))
                                    .tracking(Theme.buttonTracking)
                                    .foregroundStyle(Theme.miss)
                                    .padding(.vertical, 11)
                                    .padding(.horizontal, 18)
                                    .frame(minHeight: 44)
                                    .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                                        .strokeBorder(Theme.miss.opacity(0.5), lineWidth: 1))
                                    .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }

                    section("Debug") {
                        // Which faces actually resolved. A missing font does not
                        // error — it silently substitutes San Francisco, which is
                        // exactly how the old body face went missing everywhere
                        // once before. Only the display face can fail now; the
                        // body face IS San Francisco.
                        Text(KotekFonts.summary)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(KotekFonts.displayRegular == nil ? Theme.miss : Theme.stone)

                        FlowLayout(spacing: 10) {
                            SecondaryButton(title: "Test Mallet", systemImage: "scope") { app.openMalletTest() }
                            SecondaryButton(title: "Test Detection", systemImage: "dot.radiowaves.left.and.right") { app.openDetectionTest() }
                            SecondaryButton(title: "Test Audio", systemImage: "waveform.circle") { app.openAudioTest() }
                            SecondaryButton(title: "Capture Training Data", systemImage: "camera.viewfinder") { app.openCaptureTraining() }
                        }
                    }

                    section("Practice tempo") {
                        Picker("Tempo", selection: $app.tempoScale) {
                            ForEach(Theme.tempoScales, id: \.self) { scale in
                                Text(Theme.tempoLabel(scale)).tag(scale)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 400)

                        Text("Also on the practice screen, where it can be changed without stopping. Above 1× is faster than the figure is notated.")
                            .font(.sans(13)).foregroundStyle(Theme.stone).frame(maxWidth: 400)
                    }

                    section("Audio cues") {
                        Toggle("Metronome click", isOn: $app.metronomeEnabled)
                            .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.charcoal)
                        Toggle("Reference tone (one beat ahead)", isOn: $app.referenceToneEnabled)
                            .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.charcoal)
                        Toggle("Play my half as a guide", isOn: $app.yourVoiceAudible)
                            .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.charcoal)
                        Text(app.yourVoiceAudible
                             ? "The app sounds the part you are learning, in time with the bilah, so you can copy it. Turn it off once the figure is in your hands — it is played back on the same keys you strike, so it also makes you harder to hear."
                             : "The bilah light up but stay silent. The only strokes in the room are yours.")
                            .font(.sans(13)).foregroundStyle(Theme.stone).frame(maxWidth: 360)

                        Toggle("Partner plays the other half", isOn: $app.partnerAudible)
                            .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.charcoal)
                        Text(app.partnerAudible
                             ? "The app takes the other half, so the kotekan interlocks even when you practise alone. The gong layer is always there."
                             : "You play against the gong alone. Turn this on once the figure is steady — that is when it becomes a kotekan.")
                            .font(.sans(13)).foregroundStyle(Theme.stone).frame(maxWidth: 360)
                    }

                    section("Judging") {
                        HStack {
                            Text("Timing")
                                .font(.sans(15)).foregroundStyle(Theme.charcoal)
                            Spacer()
                            Text(app.judgementLeniency <= 1.05 ? "As notated"
                                 : (app.judgementLeniency >= 1.25 ? "Very forgiving" : "Forgiving"))
                                .font(.sans(15)).foregroundStyle(Theme.stone)
                        }
                        .frame(maxWidth: 360)
                        Slider(value: $app.judgementLeniency, in: 1.0...1.3, step: 0.05)
                            .tint(Theme.terracotta).frame(maxWidth: 360)
                        Text(app.judgementLeniency <= 1.05
                             ? "A stroke has to land where the figure puts it. The honest setting, and the hardest."
                             : "The same stroke earns a better grade, so a visitor who finds the right bilah is told so. It does not change whether a stroke registers — only what it scores.")
                            .font(.sans(13)).foregroundStyle(Theme.stone).frame(maxWidth: 360)

                        Toggle("Score wrong bars", isOn: $app.scoresWrongBar)
                            .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.charcoal)
                        Text(app.scoresWrongBar
                             ? "A stroke on the wrong bilah takes the note that was due and scores it wrong. Right when the microphone is listening — a sound means a real stroke. On camera alone, a mallet travelling across a bar can take a note you were about to play."
                             : "A stroke on a bilah nothing is due on is ignored, and the note stays open for the right one. A bar genuinely played wrong becomes a miss instead.")
                            .font(.sans(13)).foregroundStyle(Theme.stone).frame(maxWidth: 360)

                        Toggle("Call each stroke", isOn: $app.callsStrokes)
                            .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.charcoal)
                        Text(app.callsStrokes
                             ? "Each stroke says what it was — Perfect, Late, Miss — on the bilah you struck, and is gone within a second. A missed note leaves no other mark, so without this it simply disappears."
                             : "The bilah stay wordless. You will see a stroke land and nothing at all when one does not.")
                            .font(.sans(13)).foregroundStyle(Theme.stone).frame(maxWidth: 360)
                    }

                    section("Camera") {
                        Toggle("Fixed mount (stand or arm)", isOn: $app.fixedMount)
                            .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.charcoal)
                        Text(app.fixedMount
                             ? "Focus and exposure lock once the scene is set. Steadier image, and the keys stay where you aligned them — the right choice on a stand."
                             : "Focus and exposure follow the scene, for a handheld phone. On a stand this hunts every time a hand crosses the keys.")
                            .font(.sans(13)).foregroundStyle(Theme.stone).frame(maxWidth: 360)
                    }

                    section("Detection") {
                        //R ONE choice, where there were two switches whose names
                        //R gave no clue how they combined — and one of which did
                        //R the opposite of what it said: "require strike sound"
                        //R added a third trigger rather than requiring anything.
                        //R
                        //R It is the first thing to reach for when the app stops
                        //R registering strikes, or starts registering ones
                        //R nobody played, so it lives here rather than only in
                        //R the debug screens. Hunting for it under Test
                        //R Detection is not something anyone does mid-session.
                        Picker("Detection", selection: Binding(
                            get: { app.detectionMode },
                            set: { app.detectionMode = $0 }
                        )) {
                            ForEach(AppState.DetectionMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 400)

                        Text(app.detectionMode.detail)
                            .font(.sans(13)).foregroundStyle(Theme.stone).frame(maxWidth: 400)

                        if app.detectionMode == .heardOnly, app.yourVoiceAudible {
                            Text("Your half is playing through the speaker on the same keys you strike, which raises the bar an attack has to clear. Mute it under Audio cues if strikes start going missing.")
                                .font(.sans(13)).foregroundStyle(Theme.miss).frame(maxWidth: 400)
                        }
                    }
                    // This is the instrument's own settings — everything that
                    // used to be a control on its card in the picker. Naming
                    // first, because it is the only thing here you author; then
                    // the two calibration steps in the order setup runs them;
                    // then leaving, then deleting, last and apart.
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 28)
            }
        }
        .onAppear { draftName = app.profile.name }
        // The picker can change the active instrument under this screen.
        .onChange(of: app.profile.id) { _, _ in draftName = app.profile.name }
        .confirmationDialog("Delete this gangsa?",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Delete \(app.profile.name)", role: .destructive) {
                app.deleteInstrument(app.profile.id)
                app.openChooseInstrument()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its key alignment and learned voice go with it. This cannot be undone.")
        }
    }

    /// The grade in full: rung, what it is called in English, how many notes
    /// have landed on this instrument, and what the next rung costs.
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

    /// Write the typed name back, if it is actually a change.
    ///
    /// Guards an empty string by restoring rather than saving: a nameless
    /// instrument is unpickable on the rail, and clearing the field is much more
    /// likely to be a half-finished edit than an intention.
    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draftName = app.profile.name
            return
        }
        guard trimmed != app.profile.name else { return }
        var updated = app.profile
        updated.name = trimmed
        app.profile = updated
        app.saveInstrument(updated)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title)
            content()
        }
    }
}

/// Custom wrapping flow layout for inline-block wrapping of pill buttons.
struct FlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                                  proposal: ProposedViewSize.unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxW = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var points: [CGPoint] = []
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize.unspecified)
            if currentX + size.width > maxW, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: totalWidth, height: totalHeight), points)
    }
}

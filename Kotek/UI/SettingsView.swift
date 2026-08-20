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
                    // This is the instrument's own settings — everything that
                    // used to be a control on its card in the picker. Naming
                    // first, because it is the only thing here you author; then
                    // the two calibration steps in the order setup runs them;
                    // then leaving, then deleting, last and apart.
                    section(app.profile.name) {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Name")
                                    .font(.sans(13, weight: .medium))
                                    .foregroundStyle(Theme.cream.opacity(0.55))

                                TextField("Instrument name", text: $draftName)
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

                            Text("\(app.profile.keyCount) keys · \(app.profile.calibratedKeyCount) tuned · \(app.profile.hasLearnedBaseline ? "voice learned" : "no voice yet")")
                                .font(.sans(14))
                                .foregroundStyle(Theme.cream.opacity(0.62))

                            FlowLayout(spacing: 10) {
                                SecondaryButton(title: "Re-align keys", systemImage: "viewfinder") { app.realign() }
                                SecondaryButton(title: "Calibrate voice", systemImage: "waveform") { app.openCalibration() }
                                SecondaryButton(title: "Switch instrument", systemImage: "arrow.triangle.2.circlepath") { app.openChooseInstrument() }
                            }

                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete this instrument", systemImage: "trash")
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
                            Text("50%").tag(0.5)
                            Text("75%").tag(0.75)
                            Text("100%").tag(1.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)
                    }

                    section("Audio cues") {
                        Toggle("Metronome click", isOn: $app.metronomeEnabled)
                            .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.charcoal)
                        Toggle("Reference tone (one beat ahead)", isOn: $app.referenceToneEnabled)
                            .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.charcoal)
                        Toggle("Partner plays the other half", isOn: $app.partnerAudible)
                            .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.charcoal)
                        Text(app.partnerAudible
                             ? "The app plays the half you're not playing, so the kotekan interlocks even when you practise alone. The gong layer is always there."
                             : "You play against the gong alone.")
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
                        // THE lever when detection stops working in a room.
                        //
                        // With this on, nothing registers until the microphone
                        // hears an attack — the camera only names the key. The
                        // onset detector measures a strike against a rolling
                        // MEDIAN of recent loudness, so anything that raises the
                        // noise floor raises the bar a strike has to clear: a
                        // busy room, and the app's own cues coming back off the
                        // speaker (echo cancellation is off, because it would
                        // corrupt the very analysis this depends on).
                        //
                        // That is why detection can be perfect on the test
                        // screen, which plays nothing, and hopeless in a session
                        // that is playing your partner's half, the gong and a
                        // metronome. Turning this off lets the camera fire
                        // strikes on its own and ignore the racket entirely.
                        //
                        // It is here rather than only in the debug screen
                        // because it is the first thing to reach for when the
                        // app cannot hear, and hunting for it under Test
                        // Detection is not something anyone does mid-exhibition.
                        Toggle("Sound triggers strikes", isOn: $app.audioTriggersStrikes)
                            .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.charcoal)
                        Text(app.audioTriggersStrikes
                             ? "A strike counts when the mic hears the attack and the camera names the key. Most accurate in a quiet room. In a loud one — or with the partner and metronome playing — the ear's threshold rises and real strikes stop clearing it."
                             : "The camera fires strikes by itself and the room is ignored. Turn this on for a noisy space. Repeated notes on the same key can be missed, because the mallet lingering over a bar reads as one long strike.")
                            .font(.sans(13)).foregroundStyle(Theme.stone).frame(maxWidth: 360)

                        Toggle("Require strike sound", isOn: $app.requireStrikeSound)
                            .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.charcoal)
                        Text(app.requireStrikeSound
                             ? "A hit only counts with a real gangsa strike sound — blocks hovering, but needs a learned baseline (Test Audio)."
                             : "Vision alone counts the hit. More forgiving; a hovered mallet can register.")
                            .font(.sans(13)).foregroundStyle(Theme.stone).frame(maxWidth: 360)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 28)
            }
        }
        .onAppear { draftName = app.profile.name }
        // The picker can change the active instrument under this screen.
        .onChange(of: app.profile.id) { _, _ in draftName = app.profile.name }
        .confirmationDialog("Delete this instrument?",
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

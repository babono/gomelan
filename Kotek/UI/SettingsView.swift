//
//  SettingsView.swift
//  Kotek
//
//  Settings (PRD §8): recalibrate, tempo, audio cues, detection, and the dev
//  test screens.
//
//  Long enough to need a map. A landscape phone shows about two cards at a time
//  out of seven, so the rail under the title does three jobs: it says how much
//  there is, it says where you are, and it takes you there. It is a scroll-spy,
//  not a tab bar — the content is one scroll and always was; the rail only
//  reports on it.
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

    /// Where each card is, in the scroll's own space — so `minY` is distance
    /// from the top of the visible area and goes negative as a card leaves.
    /// The height is kept too; `tailInset` needs it.
    ///
    /// A box rather than `@State` of its own, and this is the point of it: every
    /// card reports a new frame on every frame of a scroll, and holding those in
    /// state would invalidate this whole screen — seven cards, two pickers, a
    /// slider and eight switches — 120 times a second to move one chip. The box
    /// absorbs the traffic; only `active` and `tailInset` are published, and
    /// they change a handful of times per scroll.
    @State private var metrics = SectionMetrics()
    /// The chip the spy has settled on. See `activeSection` for the one to read.
    @State private var active: SettingsSection = .instrument
    @State private var tailInset: CGFloat = 22
    /// The scroll viewport's height.
    @State private var viewport: CGFloat = 0
    /// Set while a tap-to-jump is animating. See `jump(to:using:)`.
    @State private var jumpTarget: SettingsSection?
    @State private var jumpToken = 0

    private static let scrollSpace = "settingsScroll"
    private static func chipID(_ id: SettingsSection) -> String { "chip-" + id.rawValue }
    /// How far down the viewport a card's top has to have climbed before it
    /// counts as the one being read. Zero would flip the chip only once a card
    /// is exactly flush with the top, which never quite happens mid-drag.
    private static let activeThreshold: CGFloat = 40

    /// The chip the rail should be lighting.
    ///
    //R A tap pins it for the length of its animation. Without that the spy
    //R lights every section the scroll flies past on the way down, which reads
    //R as the rail malfunctioning rather than as a jump.
    private var activeSection: SettingsSection { jumpTarget ?? active }

    /// Recompute what the rail says, from frames that have just moved.
    ///
    /// Called on every geometry report and writes state only when the answer
    /// actually changes — which is what keeps the box in front of it worth
    /// having.
    private func spy() {
        // The last card whose top has passed the line: the cards are laid out in
        // `allCases` order, so the deepest one that has climbed past it is the
        // one filling the screen.
        let passed = SettingsSection.allCases.filter {
            (metrics.frames[$0]?.minY ?? .greatestFiniteMagnitude) <= Self.activeThreshold
        }
        let next = passed.last ?? .instrument
        if next != active { active = next }

        // Blank space after the last card, sized so that card can climb to the
        // top of the viewport like every other one. Without it the last section
        // is unreachable by the spy: a short card at the end of a scroll stops
        // with its top halfway down the screen, so the rail would sit on
        // "Camera" while Detection is the only thing on screen. Depends on that
        // card's HEIGHT and the viewport, never on a scroll offset, so it cannot
        // feed back into the layout that produced it.
        if let last = SettingsSection.allCases.last,
           let frame = metrics.frames[last], viewport > 0 {
            let wanted = max(22, viewport - frame.height - 22)
            if abs(wanted - tailInset) > 0.5 { tailInset = wanted }
        }
    }

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            TopBar(title: "Settings",
                   backTitle: "Done",
                   onBack: { app.closeSettings() })

            ScrollViewReader { scroll in
                rail(using: scroll)

                Rectangle()
                    .fill(Theme.cream.opacity(0.10))
                    .frame(height: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        section(.instrument) {
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Name")
                                        .font(.sans(13, weight: .medium))
                                        .foregroundStyle(Theme.cream.opacity(0.62))

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
                                .buttonStyle(.kajar)
                                .padding(.top, 4)
                            }
                        }

                        section(.debug) {
                            // Which faces actually resolved. A missing font does not
                            // error — it silently substitutes San Francisco, which is
                            // exactly how the old body face went missing everywhere
                            // once before. Only the display face can fail now; the
                            // body face IS San Francisco.
                            Text(KotekFonts.summary)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(KotekFonts.displayRegular == nil ? Theme.miss : Theme.cream.opacity(0.75))

                            FlowLayout(spacing: 10) {
                                SecondaryButton(title: "Test Mallet", systemImage: "scope") { app.openMalletTest() }
                                SecondaryButton(title: "Test Detection", systemImage: "dot.radiowaves.left.and.right") { app.openDetectionTest() }
                                SecondaryButton(title: "Test Audio", systemImage: "waveform.circle") { app.openAudioTest() }
                                SecondaryButton(title: "Capture Training Data", systemImage: "camera.viewfinder") { app.openCaptureTraining() }
                            }
                        }

                        section(.tempo) {
                            Picker("Tempo", selection: $app.tempoScale) {
                                ForEach(Theme.tempoScales, id: \.self) { scale in
                                    Text(Theme.tempoLabel(scale)).tag(scale)
                                }
                            }
                            .pickerStyle(.segmented)
                            .kajarOnChange(of: app.tempoScale)
                            .frame(maxWidth: 400)

                            Text("Also on the practice screen, where it can be changed without stopping. Above 1× is faster than the figure is notated.")
                                .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 400)
                        }

                        section(.audio) {
                            Toggle("Metronome click", isOn: $app.metronomeEnabled)
                                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
                            Toggle("Reference tone (one beat ahead)", isOn: $app.referenceToneEnabled)
                                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
                            Toggle("Play my half as a guide", isOn: $app.yourVoiceAudible)
                                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
                            Text(app.yourVoiceAudible
                                 ? "The app sounds the part you are learning, in time with the bilah, so you can copy it. Turn it off once the figure is in your hands — it is played back on the same keys you strike, so it also makes you harder to hear."
                                 : "The bilah light up but stay silent. The only strokes in the room are yours.")
                                .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 360)

                            Toggle("Partner plays the other half", isOn: $app.partnerAudible)
                                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
                            Text(app.partnerAudible
                                 ? "The app takes the other half, so the kotekan interlocks even when you practise alone. The gong layer is always there."
                                 : "You play against the gong alone. Turn this on once the figure is steady — that is when it becomes a kotekan.")
                                .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 360)
                        }

                        section(.judging) {
                            HStack {
                                Text("Timing")
                                    .font(.sans(15)).foregroundStyle(Theme.cream)
                                Spacer()
                                Text(app.judgementLeniency <= 1.05 ? "As notated"
                                     : (app.judgementLeniency >= 1.25 ? "Very forgiving" : "Forgiving"))
                                    .font(.sans(15)).foregroundStyle(Theme.cream.opacity(0.75))
                            }
                            .frame(maxWidth: 360)
                            Slider(value: $app.judgementLeniency, in: 1.0...1.3, step: 0.05)
                                .tint(Theme.terracotta).frame(maxWidth: 360)
                            Text(app.judgementLeniency <= 1.05
                                 ? "A stroke has to land where the figure puts it. The honest setting, and the hardest."
                                 : "The same stroke earns a better grade, so a visitor who finds the right bilah is told so. It does not change whether a stroke registers — only what it scores.")
                                .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 360)

                            Toggle("Score wrong bars", isOn: $app.scoresWrongBar)
                                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
                            Text(app.scoresWrongBar
                                 ? "A stroke on the wrong bilah takes the note that was due and scores it wrong. Right when the microphone is listening — a sound means a real stroke. On camera alone, a mallet travelling across a bar can take a note you were about to play."
                                 : "A stroke on a bilah nothing is due on is ignored, and the note stays open for the right one. A bar genuinely played wrong becomes a miss instead.")
                                .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 360)

                            Toggle("Call each stroke", isOn: $app.callsStrokes)
                                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
                            Text(app.callsStrokes
                                 ? "Each stroke says what it was — Perfect, Late, Miss — on the bilah you struck, and is gone within a second. A missed note leaves no other mark, so without this it simply disappears."
                                 : "The bilah stay wordless. You will see a stroke land and nothing at all when one does not.")
                                .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 360)
                        }

                        section(.camera) {
                            Toggle("Fixed mount (stand or arm)", isOn: $app.fixedMount)
                                .tint(Theme.terracotta).frame(maxWidth: 360).foregroundStyle(Theme.cream)
                            Text(app.fixedMount
                                 ? "Focus and exposure lock once the scene is set. Steadier image, and the keys stay where you aligned them — the right choice on a stand."
                                 : "Focus and exposure follow the scene, for a handheld phone. On a stand this hunts every time a hand crosses the keys.")
                                .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 360)
                        }

                        section(.detection) {
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
                            .kajarOnChange(of: app.detectionMode)
                            .frame(maxWidth: 400)

                            Text(app.detectionMode.detail)
                                .font(.sans(13)).foregroundStyle(Theme.cream.opacity(0.75)).frame(maxWidth: 400)

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
                    //R The guide panel's own margins, so a card here sits where
                    //R a panel there does.
                    .padding(.horizontal, 28)
                    .padding(.top, 22)
                    .padding(.bottom, tailInset)
                }
                .coordinateSpace(.named(Self.scrollSpace))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    viewport = $0
                    spy()
                }
            }
        }
        .onAppear { draftName = app.profile.name }
        // The picker can change the active instrument under this screen.
        .onChange(of: app.profile.id) { _, _ in draftName = app.profile.name }
        .confirmationDialog("Delete this gangsa?",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            // The two buttons in the app that cannot take `.buttonStyle(.kajar)`
            // — a confirmation dialog draws its own and discards any style it is
            // given — so they strike the tick from their actions instead.
            Button("Delete \(app.profile.name)", role: .destructive) {
                KajarTick.strike()
                app.deleteInstrument(app.profile.id)
                app.openChooseInstrument()
            }
            Button("Cancel", role: .cancel) { KajarTick.strike() }
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

    /// A settings section, wearing the guide modal's panel: `deep` fill, a cream
    /// hairline, radius 22.
    ///
    /// The sections used to be headings and controls straight on the ground,
    /// separated by 30pt of nothing — which asks the eye to infer the grouping
    /// from spacing alone, down a scroll long enough that the heading is often
    /// off-screen by the time you reach the switch it governs. A card is the
    /// same grouping, stated. And it is the panel this app already uses for
    /// "here is a block of related stuff", so it needed no new design.
    @ViewBuilder
    private func section<Content: View>(_ id: SettingsSection, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(heading(id))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(Theme.deep, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22)
            .strokeBorder(Theme.cream.opacity(0.12), lineWidth: 1))
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(Self.scrollSpace))
        } action: {
            metrics.frames[id] = $0
            spy()
        }
        // The scroll target, outermost so nothing wraps it.
        .id(id)
    }

    /// The instrument's card is headed with its name, so the one section whose
    /// title is authored by the player reads as theirs.
    private func heading(_ id: SettingsSection) -> String {
        id == .instrument ? app.profile.name : id.title
    }

    private func chipLabel(_ id: SettingsSection) -> String {
        id == .instrument ? app.profile.name : id.chip
    }

    // MARK: - The rail

    /// The section list under the title: where you are, and how to get anywhere.
    ///
    /// Horizontally scrollable even though seven short chips fit a landscape
    /// phone — the first one is the instrument's name, which the player types,
    /// and a name can be any length at all.
    private func rail(using scroll: ScrollViewProxy) -> some View {
        ScrollViewReader { railScroll in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SettingsSection.allCases) { id in
                        chip(id, using: scroll)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
            }
            //R Carry the rail to the active chip as well: on a narrow screen the
            //R chip that says where you are is worth nothing off the end of it.
            .onChange(of: activeSection) { _, id in
                withAnimation(.snappy(duration: 0.25)) {
                    railScroll.scrollTo(Self.chipID(id), anchor: .center)
                }
            }
        }
    }

    private func chip(_ id: SettingsSection, using scroll: ScrollViewProxy) -> some View {
        let active = id == activeSection
        return Button {
            jump(to: id, using: scroll)
        } label: {
            Text(chipLabel(id))
                .font(.sans(12, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.6)
                .foregroundStyle(active ? Theme.onButtonFill : Theme.cream.opacity(0.6))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 34)
                .background(active ? Theme.buttonFill : .clear,
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(active ? .clear : Theme.cream.opacity(0.18), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.kajar)
        .animation(.snappy(duration: 0.2), value: active)
        //R Not `.id(id)`: the rail sits INSIDE the content's `ScrollViewReader`
        //R as well as its own, so a chip and its card answering to the same id
        //R would leave `scrollTo` choosing between two views — and only one of
        //R them is the one worth scrolling to.
        .id(Self.chipID(id))
    }

    /// Jump to a section, and hold the rail on it until the scroll settles.
    ///
    /// The token guards a second tap arriving mid-flight: without it the first
    /// tap's timer would unpin the second tap's target early, and the rail would
    /// snap back to whatever the scroll happened to be passing.
    private func jump(to id: SettingsSection, using scroll: ScrollViewProxy) {
        jumpTarget = id
        jumpToken += 1
        let token = jumpToken
        withAnimation(.snappy(duration: 0.35)) { scroll.scrollTo(id, anchor: .top) }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            if jumpToken == token { jumpTarget = nil }
        }
    }
}

/// The scroll positions the rail watches, kept OUT of view state on purpose —
/// see `SettingsView.metrics`.
@MainActor
private final class SectionMetrics {
    var frames: [SettingsSection: CGRect] = [:]
}

/// The settings sections, in the order they are laid out.
///
/// `allCases` IS the running order — the rail reads "where am I" as the last
/// case whose card has passed the top of the screen, which is only true while
/// this order and the order of the `section(_:)` calls agree. Move one, move
/// both.
enum SettingsSection: String, CaseIterable, Identifiable {
    case instrument, debug, tempo, audio, judging, camera, detection

    var id: String { rawValue }

    /// The card heading. `.instrument` has none here: it is headed with the
    /// gangsa's name, which only the view can supply.
    var title: String {
        switch self {
        case .instrument: ""
        case .debug:      "Debug"
        case .tempo:      "Practice tempo"
        case .audio:      "Audio cues"
        case .judging:    "Judging"
        case .camera:     "Camera"
        case .detection:  "Detection"
        }
    }

    /// The rail label — shorter than the heading where the heading has room to
    /// be a sentence and the chip does not.
    var chip: String {
        switch self {
        case .tempo: "Tempo"
        case .audio: "Audio"
        default:     title
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

//
//  Components.swift
//  Kotek
//
//  Shared UI pieces, in the Kotek design language: one paper ground,
//  charcoal type, orange headings, capsule buttons.
//
//  Every action control is solid (`Buttons/`, drawn by `AppControlSurface`):
//  filled with the primary for the screen's way on, the beige surface for
//  the rest. It was Liquid Glass until the November 2026 redesign — glass is
//  iOS-only and the app is going to Android. One look for one kind of control
//  is still the rule; three (glass bars, opaque gold, a flat wash) is what
//  read as inconsistent before. What you tap that is not a control — cards,
//  grid cells, tab rails, dots, the dev screens — stays `.appPlain`.
//

import SwiftUI

// MARK: - The tick under every control

/// Every switch in the app ticks when it flips.
///
/// Set ONCE, on the root — unlike `.appPlain` on buttons, which has to be written
/// at each call site because every button in this codebase already names
/// `.plain` and an explicit style beats an inherited one. Nothing sets a toggle
/// style, so the environment carries this everywhere by itself.
///
/// Drawn rather than `.switch`, since the Nawa Sanga design system: Pandan
/// when on, Garis when off, a white thumb. The system switch takes a tint for
/// ON only — its off track stays the system grey, which on the Putih canvas
/// read as disabled.
struct AppToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Capsule()
                .fill(configuration.isOn ? Theme.ok : Theme.hairline)
                .frame(width: 51, height: 31)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Theme.surface)
                        .shadow(color: Theme.ireng.opacity(0.18), radius: 1.5, y: 1)
                        .padding(3)
                }
                .opacity(isEnabled ? 1 : 0.45)
                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: configuration.isOn)
                // The HIG target, round a 31pt track.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .onTapGesture { configuration.isOn.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? Text("On") : Text("Off"))
        .accessibilityAction { configuration.isOn.toggle() }
        // On the VALUE, not on the touch, so a change made any way —
        // VoiceOver included — sounds the same.
        .onChange(of: configuration.isOn) {
            KajarTick.strike()
        }
    }
}

extension ToggleStyle where Self == AppToggleStyle {
    static var app: AppToggleStyle {
        AppToggleStyle()
    }
}

extension View {
    /// Strike the tick whenever `value` changes.
    ///
    /// For the controls that are not buttons and give no press to hook — a
    /// `Toggle`, a segmented `Picker`, a `Menu` selection. Driven by the value
    /// rather than by the touch on purpose: these are the controls where the
    /// tap and the change are not the same event, and the change is the one the
    /// player is listening for.
    ///
    /// Deliberately NOT used on the sliders. A slider changes continuously, and
    /// a kajar per step is a machine gun.
    func kajarOnChange(of value: some Equatable) -> some View {
        onChange(of: value) {
            KajarTick.strike()
        }
    }
}

// MARK: - Top bar

/// The consistent screen header: optional back affordance, centred display
/// title, optional trailing status text. `tint` is the strong text colour for
/// the surface; supporting text is derived from it.
///
/// The title is set in Katibeh — this is the app's voice, and a screen
/// title is the one piece of chrome big enough to carry it. Everything else in
/// the bar stays San Francisco, because back affordances and step counters are
/// interface rather than voice.
///
/// There is no rule under the bar. A hairline is how you separate a header from
/// content that would otherwise run into it; here the content is cards and
/// generous space on a dark ground, so the line was drawing a boundary the
/// layout already made — and putting a hard horizontal edge across a screen
/// whose whole character is soft.
struct TopBar: View {
    var title: LocalizedStringKey
    /// A line under the title saying what the screen is about — the kotekan
    /// picker's "On Pemade 1".
    var subtitle: LocalizedStringKey?
    /// nil is plain Back: a chevron in a beige circle. A title is for a leading
    /// action that is not simply "back" — Done, Cancel, Skip, Rescan — and
    /// shows as words in a beige capsule.
    var backTitle: LocalizedStringKey?
    var onBack: (() -> Void)?
    var trailingText: LocalizedStringKey?
    /// A trailing action in words — a setup step's Skip / Done, in the corner
    /// so the leading slot stays Back. Secondary, as Settings' Done.
    var trailingTitle: LocalizedStringKey?
    var onTrailing: (() -> Void)?
    /// When set, a gear button is shown at the trailing edge (e.g. open Settings).
    var settingsAction: (() -> Void)?
    /// When set, a help button is shown at the trailing edge, before the gear.
    var infoAction: (() -> Void)?
    /// What the help button opens, for VoiceOver.
    var infoLabel: LocalizedStringKey = "How Kotek works"
    /// When set, a status dot in the far corner, beside the gear — e.g. the
    /// kotekan picker's "sensors connected".
    var status: (color: Color, label: String)?
    var tint: Color = Theme.heading
    var accent: Color = Theme.description
    /// Slimmer header with no divider — used over full-bleed camera screens.
    var compact: Bool = false
    /// Folds the gear and the strike-controller status into one ⋯ menu, as the
    /// pickers draw it: the status is worth a glance, not a corner of its own.
    var showsMenu: Bool = false
    /// A control before the trailing ones — the kotekan picker's Solo / Co-op
    /// menu. It was a Co-op button, first a gold primary, which shouted over
    /// the carousel it sits above; keep whatever goes here secondary.
    var accessory: AnyView?
    /// Space between the controls and the safe-area edge. The pickers pass 0 so
    /// the buttons sit in the corners, on the line their carousel ends at.
    var edgeInset: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            Group {
                HStack(spacing: 14) {
                    // R Was "‹ Back" as bare text, then a chevron in a flat
                    // R wash, then glass, then a solid beige circle. White on
                    // R a Garis edge now — the design system's back button.
                    if let onBack {
                        if let backTitle {
                            AppButton(title: backTitle, action: onBack)
                        } else {
                            AppIconButton(
                                systemImage: "chevron.left",
                                label: "Back",
                                action: onBack
                            )
                        }
                    }
                    titleBlock
                    Spacer(minLength: 14)
                    if let trailingText {
                        Text(trailingText)
                            .font(.sans(13, weight: .medium))
                            .foregroundStyle(accent)
                    }
                    if let trailingTitle, let onTrailing {
                        AppButton(title: trailingTitle, action: onTrailing)
                    }
                    if let accessory {
                        accessory
                    }
                    // 44pt circles: a bare glyph in a corner is a 19pt
                    // target, and the HIG minimum is 44.
                    if let infoAction {
                        AppIconButton(
                            systemImage: "questionmark",
                            label: infoLabel,
                            action: infoAction
                        )
                    }
                    if showsMenu {
                        MoreMenu(settingsAction: settingsAction)
                    } else if let settingsAction {
                        AppIconButton(
                            systemImage: "gearshape",
                            label: "Settings",
                            action: settingsAction
                        )
                    }
                    if let status {
                        Circle()
                            .fill(status.color)
                            .frame(width: 10, height: 10)
                            .accessibilityElement()
                            .accessibilityLabel(status.label)
                    }
                }
            }
            .padding(.horizontal, edgeInset)
            .padding(.top, compact ? 10 : 18)
            // Room for the subtitle, which hangs below the row.
            .padding(.bottom, (compact ? 8 : 12) + (subtitle == nil ? 0 : 16))
        }
    }

    /// Top left, beside Back. It sat centred in uppercase until the pickers
    /// grew Mode and ⋯ on the right: a centred title had to be padded clear of
    /// the widest side, and still read off-centre. Leading, in sentence case,
    /// it only has to stop where the controls start.
    private var titleBlock: some View {
        let size: CGFloat = compact ? 22 : 28
        return Text(title)
            .font(.serif(size))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            // Katibeh sits high in its line box (a deep descender), so the
            // title is nudged down to the buttons' middle.
            .offset(y: size * 0.15)
            // An overlay, so the subtitle never moves the title off the
            // buttons' line.
            .overlay(alignment: .topLeading) {
                if let subtitle {
                    Text(subtitle)
                        .font(.sans(13))
                        .foregroundStyle(Theme.stone)
                        .lineLimit(1)
                        .fixedSize()
                        .offset(y: size * 1.3)
                }
            }
            .layoutPriority(-1)
    }
}

/// The ⋯ in a picker's top bar: the sensor's state, then Settings.
private struct MoreMenu: View {
    @Environment(AppState.self) private var app
    let settingsAction: (() -> Void)?

    var body: some View {
        let status = SensorIndicator.summary(for: app)
        Menu {
            // A row that reports, not an action: disabled so it reads as status.
            Button {} label: { Label { Text(status.text) } icon: { status.icon } }
                .disabled(true)
            if let settingsAction {
                Button("Settings", systemImage: "gearshape", action: settingsAction)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.symbol(AppButtonSize.regular.symbolPoints, weight: .semibold))
                .foregroundStyle(Theme.cream)
                .frame(width: AppButtonSize.regular.height, height: AppButtonSize.regular.height)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // The circle outside the menu, as `AppMenuPicker` draws its pill: the
        // system redraws a menu's label as it opens and closes, and dropped
        // the edge for a frame.
        .tactile(
            Circle(),
            fill: Theme.glassTint,
            outline: Theme.hairline,
            base: Theme.hairline,
            depth: AppButtonSize.regular.depth
        )
        .overlay(alignment: .topTrailing) {
            if app.controllerNeedsCheck {
                Circle().fill(Theme.wrong).frame(width: 9, height: 9)
            }
        }
        .accessibilityLabel("More, \(status.text)")
    }
}

// MARK: - Labels

/// Uppercase tracked eyebrow/section label.
struct SectionLabel: View {
    let text: LocalizedStringKey
    var color: Color = Theme.description
    init(_ text: LocalizedStringKey, color: Color = Theme.description) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.sans(12, weight: .semibold))
            .textCase(.uppercase)
            .tracking(2.5)
            .foregroundStyle(color)
    }
}

// MARK: - Stat bar

/// Horizontal progress bar used on the results screen ("where it slipped").
struct StatBar: View {
    var fraction: Double
    var color: Color
    var track: Color = Theme.creamSunken

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color)
                    .frame(
                        width: max(6, geo.size.width * min(1, max(0, fraction)))
                    )
            }
        }
        .frame(height: 7)
    }
}

// MARK: - Busy

/// The scrim shown while something is genuinely being done — a profile written,
/// the lens settling on a lock, a baseline being folded into a template. Blocks
/// interaction, because every one of these steps ends in a screen change and a
/// second tap during the wait lands somewhere the player didn't aim.
///
/// Only ever shown around real work. A spinner that appears and vanishes in the
/// same frame reads as a glitch, not as progress.
struct BusyOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            // R Same scrim as `GuidePanel`. Everything that floats over a screen
            // R in this app is the same two moves — this depth of black, and the
            // R panel below — so a wait and an explainer do not read as coming
            // R from two different apps.
            Color.black.opacity(0.72).ignoresSafeArea()
            // R The card was solid cream for a while: a dark card on a dark
            // R camera feed used to disappear into it, three shades of near-black
            // R stacked up. What that missed is that `Theme.charcoal` has been an
            // R ALIAS OF CREAM since the palette went all-dark, so the label was
            // R cream on cream and the message could not be read at all.
            // R
            // R The panel colours are the guide panel's, which solve the same
            // R problem the right way round: `deep` is a step darker than the
            // R ground, so it separates from a dark feed by being darker than it
            // R rather than by being the one light thing on the screen.
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.gold)
                    .scaleEffect(1.3)
                Text(message)
                    .font(.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.cream)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 30)
            .frame(minWidth: 260)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Theme.cream.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        }
    }
}

// MARK: - Confirm

/// A yes/no the app asks in its own voice.
///
/// This replaced `.confirmationDialog`, which is a fine control and the wrong
/// one here: the system sheet arrives as a white (or system-dark) card with
/// system type and system button metrics, in a landscape-locked app that has one
/// warm ground, one type family and no light/dark flip in it — and it discards
/// any `buttonStyle` it is handed, so its buttons were the only two in the app
/// that could not strike a kajar by being buttons.
///
/// Same panel as `BusyOverlay` and `GuidePanel`, because it is the same object:
/// something floating over the screen with the app's ground under it.
struct ConfirmDialog: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let confirmTitle: LocalizedStringKey
    /// The confirming button's colour. `Theme.miss` — the app's red — for
    /// anything that destroys something, which so far is all of them.
    var confirmTint: Color = Theme.miss
    /// Kipli beside the title, in this mood — sad over losing something.
    var kipli: KipliGuide.Mood?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    /// He says the title as the dialog opens.
    @State private var talking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Tapping outside is a cancel, as it is on the guide panels. The
            // panel swallows its own taps.
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture {
                    KajarTick.strike()
                    onCancel()
                }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    if let kipli {
                        KipliFace(mood: kipli, height: 44, talking: talking)
                    }
                    Text(title)
                        .font(.serif(24))
                        .textCase(.uppercase)
                        .tracking(1.5)
                        .foregroundStyle(Theme.heading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Text(message)
                    .font(.sans(14))
                    .foregroundStyle(Theme.cream.opacity(0.75))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                Group {
                    HStack(spacing: 12) {
                        Spacer(minLength: 0)
                        AppButton(title: "Cancel", size: .compact) {
                            onCancel()
                        }
                        // R The destructive button is a secondary with type in
                        // R its own colour rather than the filled way on.
                        // R `.primary` is the app's one "do this" — and the
                        // R delete is precisely not the thing being recommended.
                        AppButton(title: confirmTitle, size: .compact, tint: confirmTint, action: onConfirm)
                    }
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Theme.cream.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
            .padding(.horizontal, 28)
        }
        .task {
            guard kipli != nil, !reduceMotion else { return }
            talking = true
            try? await Task.sleep(for: .seconds(1.2))
            talking = false
        }
    }
}

extension View {
    /// Asks `title` over this view while `isPresented`, in the app's own panel.
    ///
    /// Dismisses itself before running `action`, so the caller's handler is free
    /// to change screen without the dialog animating out over the next one.
    func confirm(
        _ isPresented: Binding<Bool>,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        confirmTitle: LocalizedStringKey,
        confirmTint: Color = Theme.miss,
        kipli: KipliGuide.Mood? = nil,
        action: @escaping () -> Void
    ) -> some View {
        overlay {
            if isPresented.wrappedValue {
                ConfirmDialog(
                    title: title,
                    message: message,
                    confirmTitle: confirmTitle,
                    confirmTint: confirmTint,
                    kipli: kipli,
                    // Act FIRST, then dismiss. The pickers present this from
                    // the thing being deleted (`pendingDelete != nil`), so
                    // dismissing first cleared it and the action found
                    // nothing to delete — Delete silently did nothing.
                    onConfirm: {
                        action()
                        isPresented.wrappedValue = false
                    },
                    onCancel: { isPresented.wrappedValue = false }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isPresented.wrappedValue)
    }
}

extension View {
    /// Covers this view with `BusyOverlay` while `message` is non-nil.
    ///
    /// No cross-fade: these waits are often under a second, and a fade meant the
    /// scrim spent a good part of its life half-transparent — which is exactly
    /// when it looks like a faint smudge rather than a loading state.
    func busy(_ message: String?) -> some View {
        overlay {
            if let message { BusyOverlay(message: message) }
        }
    }
}

// MARK: - Share sheet

/// UIActivityViewController for SwiftUI — AirDrop, Files, Mail.
///
/// Used to get captured training data off the device without making the user
/// hunt through the Files app.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ controller: UIActivityViewController,
        context: Context
    ) {}
}

/// So a URL can drive `.sheet(item:)` directly. The path is already unique,
/// which is exactly what identity means here.
extension URL: @retroactive Identifiable {
    public var id: String {
        absoluteString
    }
}

extension Comparable {
    /// `x.clamped(to: a, b)` — reads better inline than nesting min and max, and
    /// is harder to get the wrong way round.
    func clamped(to lower: Self, _ upper: Self) -> Self {
        min(max(self, lower), upper)
    }
}

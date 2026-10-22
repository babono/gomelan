//
//  Components.swift
//  Kotek
//
//  Shared UI pieces, in the Kotek design language: one warm brown ground,
//  cream type, capsule buttons.
//
//  Every action control is Liquid Glass (`Buttons/`, drawn by
//  `AppControlSurface`): gold-tinted for the screen's way on, tinted with the
//  ground for the rest.
//  That is an explicit product decision — Apple's guidance keeps glass to the
//  floating layer. What was tried before: glass for bars only, opaque gold for
//  the way on inside content, a flat 12% wash for secondaries (clear glass was
//  tried there and was still too loud). Three looks for one kind of control is
//  what read as inconsistent. What you tap that is not a control — cards, grid
//  cells, tab rails, dots, the dev screens — stays `.appPlain`.
//

import SwiftUI

// MARK: - Wordmark

/// The KOTEK wordmark, at the one size and position the app draws it.
///
/// Shared by the splash and the landing screen ON PURPOSE, and this is the
/// whole reason it is a type rather than two `Image` calls: the two screens
/// hand over by cross-fading everything AROUND the wordmark while the wordmark
/// itself stays exactly where it is. That only works if both screens agree on
/// its geometry to the point, which they cannot do if each computes its own.
///
/// Sized from the container rather than fixed, so it holds its proportions on
/// an iPad and on a small phone in landscape. The cap is what stops it turning
/// into a banner on a 13" screen.
///
/// Drawn plain, at full strength, on every screen that shows it. The splash
/// used to fill it with cream from the bottom as loading progressed; that made
/// the wordmark rise into view, which read as an entrance animation rather than
/// as progress and was the wrong thing for a mark that is supposed to be simply
/// present. The pill underneath reports progress, and reports it alone.
struct KotekWordmark: View {
    /// The width the LATIN wordmark takes. The Sanskrit below is sized from it,
    /// so one number governs the whole mark.
    let width: CGFloat

    /// The artwork's own proportions (287 x 83), so the height follows from the
    /// width and the two screens cannot drift apart.
    static let aspectRatio: CGFloat = 287.0 / 83.0
    /// The Sanskrit mark's own proportions (176 x 59).
    static let sanskritAspectRatio: CGFloat = 176.0 / 59.0

    /// How wide the Sanskrit sits under the wordmark, as a fraction of it.
    /// Narrower on purpose: it is the second mark, and matching the width would
    /// read as two logos stacked rather than one with its script beneath.
    private static let sanskritScale: CGFloat = 0.58
    private static let gapScale: CGFloat = 0.06

    /// The width the wordmark takes in a container this wide.
    static func width(in containerWidth: CGFloat) -> CGFloat {
        min(280, containerWidth * 0.25)
    }

    /// Where the top of the wordmark sits in a container this tall. Shared for
    /// the same reason as the width.
    static func topInset(in containerHeight: CGFloat) -> CGFloat {
        containerHeight * 0.17
    }

    /// The whole mark's height, script included — what a screen laying out
    /// around it needs, and the reason the width is a parameter rather than a
    /// `.frame` the caller bolts on afterwards. A `GeometryReader` in here would
    /// read the width but claim all the height going, which is precisely the
    /// layout both screens cannot afford.
    static func height(for width: CGFloat) -> CGFloat {
        width / aspectRatio
            + width * gapScale
            + (width * sanskritScale) / sanskritAspectRatio
    }

    var body: some View {
        VStack(spacing: width * Self.gapScale) {
            // Named `wordmark-kotek`, NOT `logo-kotek`. The app icon already
            // claims `logo-kotek` (see ASSETCATALOG_COMPILER_APPICON_NAME and
            // `Kotek/logo-kotek.icon`), and an asset catalog will happily
            // compile two unrelated things under one name — the icon stack and
            // this artwork — and leave `Image("logo-kotek")` to pick between
            // them. Renaming is the fix; do not name anything else
            // `logo-kotek`.
            image("wordmark-kotek", width: width, aspect: Self.aspectRatio)

            // A template image, tinted here: the export carries a gold a shade
            // off the palette's, and the script should be the title colour.
            image(
                "logo-sanskrit",
                width: width * Self.sanskritScale,
                aspect: Self.sanskritAspectRatio
            )
            .foregroundStyle(Theme.gold)
        }
        // One accessibility element: VoiceOver reading two undescribed images
        // in a row is worse than reading the name once.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kotek")
    }

    /// Both frames are given a HEIGHT as well as a width. `.fit` on its own only
    /// constrains — a resizable image in a width-only frame is free to take the
    /// height it likes, and the two marks would size independently of each
    /// other.
    private func image(_ name: String, width: CGFloat, aspect: CGFloat)
        -> some View
    {
        Image(name)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: width / aspect)
    }
}

// MARK: - The tick under every control

/// Every switch in the app ticks when it flips.
///
/// Set ONCE, on the root — unlike `.appPlain` on buttons, which has to be written
/// at each call site because every button in this codebase already names
/// `.plain` and an explicit style beats an inherited one. Nothing sets a toggle
/// style, so the environment carries this everywhere by itself.
///
/// Renders `.switch` inside, which is what these were getting from the default
/// on iOS anyway.
struct AppToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(isOn: configuration.$isOn) { configuration.label }
            .toggleStyle(.switch)
            // On the VALUE, not on the touch: a switch can also be flipped by a
            // drag across it, and that should sound the same as tapping it.
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
    var title: String
    /// nil is plain Back: a chevron in a glass circle. A title is for a leading
    /// action that is not simply "back" — Done, Cancel, Skip, Rescan — and
    /// shows as words in a glass capsule.
    var backTitle: String?
    var onBack: (() -> Void)?
    var trailingText: String?
    /// A trailing action in words — a setup step's Skip / Done, in the corner
    /// so the leading slot stays Back. Secondary glass, as Settings' Done.
    var trailingTitle: String?
    var onTrailing: (() -> Void)?
    /// When set, a gear button is shown at the trailing edge (e.g. open Settings).
    var settingsAction: (() -> Void)?
    /// When set, a help button is shown at the trailing edge, before the gear.
    var infoAction: (() -> Void)?
    /// When set, a status dot in the far corner, beside the gear — e.g. the
    /// kotekan picker's "sensors connected".
    var status: (color: Color, label: String)?
    var tint: Color = Theme.cream
    var accent: Color = Theme.gold
    /// Slimmer header with no divider — used over full-bleed camera screens.
    var compact: Bool = false
    /// Folds the gear and the strike-controller status into one ⋯ menu, as the
    /// pickers draw it: the status is worth a glance, not a corner of its own.
    var showsMenu: Bool = false
    /// A labelled button before the trailing controls — the kotekan picker's Co-op.
    /// Secondary, like Settings' Done: it was a gold primary, which shouted over
    /// the carousel it sits above.
    var accessory: (title: String, systemImage: String, isEnabled: Bool, action: () -> Void)?
    /// Space between the controls and the safe-area edge. The pickers pass 0 so
    /// the buttons sit in the corners, on the line their carousel ends at.
    var edgeInset: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(.serif(compact ? 22 : 30))
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // Never let the title grow under the controls either side.
                    // Symmetric, so it stays centred on the screen: 96 clears
                    // two circles, but Duet + ⋯ was ~170 wide, and the title
                    // ran on under Duet, which read as off-centre.
                    .padding(.horizontal, accessory == nil ? 96 : 180)
                    // Katibeh sets its capitals high in the line box (a deep
                    // descender under them), so a centred frame left the
                    // uppercase title ~7pt above the buttons' middle. Measured
                    // off a screenshot; scales with the size.
                    .offset(y: (compact ? 22 : 30) * 0.23)

                // One container for the bar's glass, as Apple recommends
                // wherever glass controls sit together: they render as one
                // pass and blend as glass should when they move.
                GlassEffectContainer(spacing: 14) {
                    HStack(spacing: 14) {
                        // R Was "‹ Back" as bare text, then a chevron in a flat
                        // R wash. Glass now: back, help and settings are the
                        // R navigation layer, which is what Liquid Glass is for —
                        // R and how iOS itself draws them.
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
                        Spacer()
                        if let trailingText {
                            Text(trailingText)
                                .font(.sans(13, weight: .medium))
                                .foregroundStyle(accent)
                        }
                        if let trailingTitle, let onTrailing {
                            AppButton(title: trailingTitle, action: onTrailing)
                        }
                        if let accessory {
                            AppButton(
                                title: accessory.title,
                                systemImage: accessory.systemImage,
                                action: accessory.action
                            )
                            .disabled(!accessory.isEnabled)
                        }
                        // 44pt circles: a bare glyph in a corner is a 19pt
                        // target, and the HIG minimum is 44.
                        if let infoAction {
                            AppIconButton(
                                systemImage: "questionmark",
                                label: "How Kotek works",
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
            }
            .padding(.horizontal, edgeInset)
            .padding(.top, compact ? 10 : 18)
            .padding(.bottom, compact ? 8 : 12)
        }
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
                .appControlSurface(size: .regular, shape: .circle, prominence: .secondary, growsHitArea: false)
                .overlay(alignment: .topTrailing) {
                    if app.controllerNeedsCheck {
                        Circle().fill(Theme.wrong).frame(width: 9, height: 9)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More, \(status.text)")
    }
}

// MARK: - Labels

/// Uppercase tracked eyebrow/section label.
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.gold
    init(_ text: String, color: Color = Theme.gold) {
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
            .background(Theme.deep, in: RoundedRectangle(cornerRadius: 22))
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
    let title: String
    let message: String
    let confirmTitle: String
    /// The confirming button's colour. `Theme.miss` — the app's red — for
    /// anything that destroys something, which so far is all of them.
    var confirmTint: Color = Theme.miss
    let onConfirm: () -> Void
    let onCancel: () -> Void

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
                Text(title)
                    .font(.serif(24))
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(message)
                    .font(.sans(14))
                    .foregroundStyle(Theme.cream.opacity(0.75))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        Spacer(minLength: 0)
                        AppButton(title: "Cancel", size: .compact) {
                            onCancel()
                        }
                        // R The destructive button is plain glass with type in
                        // R its own colour rather than the gold-tinted way on.
                        // R `.primary` is the app's one "do this" — and the
                        // R delete is precisely not the thing being recommended.
                        AppButton(title: confirmTitle, size: .compact, tint: confirmTint, action: onConfirm)
                    }
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .background(Theme.deep, in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Theme.cream.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
            .padding(.horizontal, 28)
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
        title: String,
        message: String,
        confirmTitle: String,
        confirmTint: Color = Theme.miss,
        action: @escaping () -> Void
    ) -> some View {
        overlay {
            if isPresented.wrappedValue {
                ConfirmDialog(
                    title: title,
                    message: message,
                    confirmTitle: confirmTitle,
                    confirmTint: confirmTint,
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

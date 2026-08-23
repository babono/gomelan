//
//  Components.swift
//  Kotek
//
//  Shared UI pieces, in the Kotek design language: one warm brown ground,
//  cream type, gold outlines, radius 14 throughout.
//
//  Buttons are rounded rectangles rather than capsules. That is the design's
//  call and it matters more than it sounds — a capsule reads as a chip, a 14pt
//  rectangle at 56pt tall reads as a key on an instrument, which is what these
//  screens are about.
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

    /// The artwork's own proportions (230 x 86), so the height follows from the
    /// width and the two screens cannot drift apart.
    static let aspectRatio: CGFloat = 230.0 / 86.0
    /// The Sanskrit mark's own proportions (186 x 73).
    static let sanskritAspectRatio: CGFloat = 186.0 / 73.0

    /// How wide the Sanskrit sits under the wordmark, as a fraction of it.
    /// Narrower on purpose: it is the second mark, and matching the width would
    /// read as two logos stacked rather than one with its script beneath.
    private static let sanskritScale: CGFloat = 0.46
    private static let gapScale: CGFloat = 0.02

    /// The width the wordmark takes in a container this wide.
    static func width(in containerWidth: CGFloat) -> CGFloat {
        min(300, containerWidth * 0.26)
    }

    /// Where the top of the wordmark sits in a container this tall. Shared for
    /// the same reason as the width.
    static func topInset(in containerHeight: CGFloat) -> CGFloat {
        containerHeight * 0.11
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

            image("logo-sanskrit",
                  width: width * Self.sanskritScale,
                  aspect: Self.sanskritAspectRatio)
        }
        // One accessibility element: VoiceOver reading two undescribed images
        // in a row is worse than reading the name once.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gomelan")
    }

    /// Both frames are given a HEIGHT as well as a width. `.fit` on its own only
    /// constrains — a resizable image in a width-only frame is free to take the
    /// height it likes, and the two marks would size independently of each
    /// other.
    private func image(_ name: String, width: CGFloat, aspect: CGFloat) -> some View {
        Image(name)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: width / aspect)
    }
}

// MARK: - Buttons

enum PillStyle { case filled, outlined, secondary }

/// The canonical pill button (GO, NEXT, CALIBRATE, START PRACTICE, RETRY …).
/// Labels are tracked and uppercased by default to match the spec.
struct PillButton: View {
    let title: String
    var systemImage: String? = nil
    var style: PillStyle = .outlined
    var tint: Color = Theme.gold
    var uppercase: Bool = true
    var fullWidth: Bool = false
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 8 : 10) {
                if let systemImage {
                    // Symbol metrics, not text metrics — see `Font.symbol`.
                    Image(systemName: systemImage)
                        .font(.symbol(compact ? 14 : 18, weight: .semibold))
                }
                Text(title)
                    .textCase(uppercase ? .uppercase : nil)
                    // One tracking for every button, uppercase or not: the
                    // labels are short and set heavy, and heavy short words
                    // need the air whichever case they are in.
                    .tracking(Theme.buttonTracking)
                    // SF has real weights, unlike the face this used to be, so
                    // a button label can simply BE the weight it wants.
                    .font(.sans(compact ? 14 : 19, weight: Theme.buttonWeight))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 18 : 30)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: compact ? 38 : Theme.buttonHeight)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .strokeBorder(tint, lineWidth: style == .outlined ? 1 : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            // The compact pill is drawn 38pt tall because that is what the
            // design calls for, but the HIG minimum target is 44 — so the
            // TARGET is grown to 44 without changing what is drawn. Someone
            // reaching for this is standing over an instrument holding a
            // mallet, which is not the moment for a six-point miss.
            .frame(minHeight: 44)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        // The primary button is a cream slab with dark type on it — the one
        // place in the app where ink-on-light is correct.
        case .filled: return Theme.onButtonFill
        case .outlined: return Theme.cream
        case .secondary: return Theme.cream
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .filled:
            RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.buttonFill)
        case .outlined:
            // Glass rather than a hole: a cream wash at 8% over whatever is
            // behind, which on the camera screens is the instrument itself.
            RoundedRectangle(cornerRadius: Theme.radius)
                .fill(Theme.cream.opacity(0.08))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.radius))
        case .secondary:
            RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.inkRaised)
        }
    }
}

/// The cream call-to-action. Kept as a distinct name because many call sites
/// use it; it is just a non-uppercased filled `PillButton` with an icon.
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Theme.cream
    let action: () -> Void

    var body: some View {
        PillButton(title: title, systemImage: systemImage, style: .filled,
                   tint: tint, uppercase: false, fullWidth: true, action: action)
    }
}

/// Outlined utility button. Adapts to the surface via the ambient colour scheme,
/// so it reads on both paper (light) and stage (dark) screens.
struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.symbol(15))
                }
                Text(title)
                    .font(.sans(15, weight: Theme.buttonWeight))
                    .tracking(Theme.buttonTracking)
            }
            .foregroundStyle(Theme.cream)
            .padding(.vertical, 11)
            .padding(.horizontal, 18)
            // 15pt type plus 11pt either side lands a point or two under the
            // HIG's 44pt minimum, which is exactly the kind of near-miss that
            // never gets noticed. Stated explicitly instead.
            .frame(minHeight: 44)
            .background(Theme.cream.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(Theme.gold.opacity(0.45), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Top bar

/// The consistent screen header: optional back affordance, centred display
/// title, optional trailing status text. `tint` is the strong text colour for
/// the surface; supporting text is derived from it.
///
/// The title is set in Dream Orphans — this is the app's voice, and a screen
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
    var backTitle: String? = nil
    var onBack: (() -> Void)? = nil
    var trailingText: String? = nil
    /// When set, a gear button is shown at the trailing edge (e.g. open Settings).
    var settingsAction: (() -> Void)? = nil
    var tint: Color = Theme.cream
    var accent: Color = Theme.gold
    /// Slimmer header with no divider — used over full-bleed camera screens.
    var compact: Bool = false

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
                    .padding(.horizontal, 96)

                HStack(spacing: 14) {
                    if let onBack {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                // The system back chevron, at the weight and
                                // spacing iOS itself uses for one, so it reads
                                // as Back rather than as an arrow someone drew.
                                Image(systemName: "chevron.left")
                                    .font(.symbol(16, weight: .semibold))
                                Text(backTitle ?? "Back").font(.sans(16))
                            }
                            .foregroundStyle(tint)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    if let trailingText {
                        Text(trailingText)
                            .font(.sans(13, weight: .medium))
                            .foregroundStyle(accent)
                    }
                    if let settingsAction {
                        Button(action: settingsAction) {
                            Image(systemName: "gearshape")
                                .font(.symbol(19, weight: .medium))
                                .foregroundStyle(tint)
                                // A bare 19pt glyph is a ~19pt target. The
                                // HIG minimum is 44 square, and a gear in a
                                // corner is the easiest thing in the app to
                                // miss.
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Settings")
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, compact ? 10 : 18)
            .padding(.bottom, compact ? 8 : 12)
        }
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

// MARK: - Stepper

/// A −/number/+ stepper. Big serif number, circular buttons — the shared control
/// for key count and cycle count.
struct CountStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var numberSize: CGFloat = 64
    var tint: Color = Theme.gold
    var numberColor: Color = Theme.cream
    var lineColor: Color = Theme.cream

    var body: some View {
        HStack(spacing: 22) {
            circle(system: "minus", enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - 1)
            }
            Text("\(value)")
                .font(.serif(numberSize, weight: .regular))
                .foregroundStyle(numberColor)
                .frame(minWidth: numberSize * 1.1)
                .contentTransition(.numericText())
            circle(system: "plus", enabled: value < range.upperBound) {
                value = min(range.upperBound, value + 1)
            }
        }
        .animation(.snappy(duration: 0.2), value: value)
    }

    private func circle(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.symbol(24, weight: .semibold))
                .foregroundStyle(enabled ? tint : lineColor.opacity(0.3))
                .frame(width: 64, height: 64)
                .background(
                    Circle()
                        .fill(enabled ? tint.opacity(0.08) : Color.clear)
                )
                .overlay(
                    Circle()
                        .strokeBorder(enabled ? tint.opacity(0.75) : lineColor.opacity(0.2), lineWidth: 2)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
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
                    .frame(width: max(6, geo.size.width * min(1, max(0, fraction))))
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
            Color.black.opacity(0.65).ignoresSafeArea()
            //R A dark card on a dark camera feed disappeared into it — three
            //R shades of near-black stacked on each other. Solid cream, so it
            //R reads as a lit panel over the stage whatever is behind it,
            //R including an unlit room.
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.terracotta)
                    .scaleEffect(1.3)
                Text(message)
                    .font(.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.charcoal)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 30)
            .frame(minWidth: 260)
            .background(Theme.cream, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Theme.terracotta.opacity(0.5), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        }
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

// MARK: - Realign affordance

/// A persistent "keys misaligned?" affordance (PRD §13.4).
struct RealignButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Realign", systemImage: "viewfinder")
                .font(.sans(13, weight: Theme.buttonWeight))
                .tracking(Theme.buttonTracking)
                .foregroundStyle(Theme.terracotta)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .overlay(Capsule().strokeBorder(Theme.terracotta.opacity(0.5), lineWidth: 1))
                // Drawn small on purpose — it is a persistent affordance, not a
                // call to action — but still tappable to the HIG minimum.
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// So a URL can drive `.sheet(item:)` directly. The path is already unique,
/// which is exactly what identity means here.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

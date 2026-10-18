//
//  Theme.swift
//  Kotek
//
//  The Kotek design system.
//
//  One surface, not two. The app used to run a "paper" world (cream, light) for
//  selection screens and a "stage" world (ink, dark) behind the camera, and each
//  component had to read on both. The design collapses that: everything sits on
//  the same warm brown ground with the pattern behind it, and the camera screens
//  are simply the ones where the ground happens to be a live image. Fewer
//  decisions, and the app stops flashing between light and dark mid-flow.
//
//  Palette (the October 2026 revamp) lives in the asset catalog, so the
//  designers can change a colour without a code edit:
//    Background #2A211C · PatternBackground #312721 · Card #3D322C
//    TitleText #C29A59  · DescriptionText #7A5E4E   · LoadingBar #8D3021
//  The revamp is one family — gold on brown. There is no cream any more: text
//  that was cream is the title gold, and supporting text is the description
//  brown. Cards are a step LIGHTER than the ground now, not darker.
//
//  Type: Katibeh for titles and headings — bundled, see UIAppFonts in
//  Info.plist, and falling back to the nearest system serif if a build ever
//  ships without it. It comes in one weight. Everything else is San
//  Francisco at the system weights, which is what the Human Interface
//  Guidelines ask for and what every iOS reader's eye is already calibrated
//  to.
//
//  Geometry: radius 14, primary buttons 56pt tall.
//
//  The old token NAMES are kept (`ink`, `cream`, `copper`, `terracotta` …)
//  because ~250 call sites use them and renaming would be a mechanical change
//  with no design value. What changed is what they point at.
//

import SwiftUI

enum Theme {
    // MARK: - Palette

    /// The ground. Every screen sits on this.
    static let ground = Color("Background")
    /// The motif drawn over the ground — see `PatternBackground`.
    static let pattern = Color("PatternBackground")
    /// Cards, panels and wells. The name is older than the revamp, which made
    /// cards a step lighter than the ground rather than a step darker.
    static let deep = Color("Card")
    /// Primary text. Named for the colour it used to be; it is the title gold
    /// now — the revamp has no light text, only gold on brown.
    static let cream = Color("TitleText")
    /// Outlines, eyebrows, accents, the tracked uppercase labels — and titles.
    static let gold = Color("TitleText")
    /// Supporting text: descriptions, metadata, captions.
    static let description = Color("DescriptionText")
    /// Progress — the splash's loading bar.
    static let progress = Color("LoadingBar")
    /// A bilah as it is struck, on the splash's gangsa. Read off the
    /// mockup — not on the palette sheet yet.
    static let keyHighlight = Color("KeyHighlight")
    /// A bilah the player's hand has just stopped ringing — see
    /// `GangsaTable`. Read off the mockup, like `keyHighlight`.
    static let keyDampened = Color("KeyDampened")
    /// Carved teak, for the pelawah and anything standing in for wood.
    static let wood = Color(hex: 0x8B5A32)
    /// Struck bronze — the bilah themselves.
    static let bronze = Color(hex: 0xC9A876)

    // MARK: - Legacy names, repointed

    //
    // `charcoal` and `stone` used to be dark-on-light text. Since every surface
    // is now dark, they resolve to the light end instead: the same call sites
    // still mean "strong body text" and "supporting text", which is the part
    // worth preserving.

    static let ink = ground
    static let inkRaised = deep
    static let background = ground
    static let creamSunken = deep
    static let terracotta = gold
    static let accent = gold
    static let copper = gold
    /// Strong body text.
    static let charcoal = cream
    /// Supporting text.
    static let stone = description
    static let inkStone = description

    /// Dark text for use ON a gold fill — anything sitting on `cream`. Named
    /// for the job rather than the colour.
    static let onCream = ground

    // MARK: - Button colours

    //
    // These two come from the asset catalog rather than a hex literal here, so
    // the designer can change them without a code edit. Named for the JOB, like
    // `onCream` above: `onButtonFill` is only correct on top of `buttonFill`,
    // and the pair has to move together or the label stops being legible.

    /// The filled button's slab.
    static let buttonFill = Color("Tertiary")
    /// Type sitting on that slab.
    static let onButtonFill = Color("LaunchBackground")
    /// Type on the gold-tinted glass of the main action (`glassButton(filled:)`).
    static let onGlassFill = onButtonFill

    // MARK: - Geometry

    /// Corner radius for buttons, cards and wells.
    static let radius: CGFloat = 14
    /// Height of a primary button.
    static let buttonHeight: CGFloat = 56

    /// Weight and letter-spacing shared by every button label.
    ///
    /// Held here rather than at each call site so the buttons cannot drift
    /// apart — they are the most repeated element in the app and the one place
    /// an inconsistency is most obvious. Black is the heaviest SF Pro cut, which
    /// only became available when the body face stopped being a single-weight
    /// Futura; the tracking is what keeps a short, very heavy, uppercase word
    /// from setting solid.
    static let buttonWeight: Font.Weight = .black
    static let buttonTracking: CGFloat = 1.5
    /// Opacity the background pattern is laid in at. 1: the motif is drawn in
    /// `pattern`, a colour already chosen to sit just off the ground, so there
    /// is nothing left to fade. Below 1 still scales it, for the camera
    /// screens' overlay.
    static let patternOpacity: Double = 1.0

    // MARK: - Overlay play colours (§13.5)

    static let upcoming = gold
    /// Correct hit. Warmed towards the palette rather than a stock green, but
    /// kept clearly green — it has to read as right/wrong at a glance while
    /// someone is playing.
    static let hit = Color(hex: 0x7FB069)
    static let miss = Color(hex: 0xA85A44)
    static let wrong = Color(hex: 0xD9A441)

    // MARK: - Colotomic layer (gong / kempur / kajar)

    /// One warm family — cream, amber, stone. The colotomic layer frames the
    /// cycle rather than carrying a part, so it belongs to the ground rather
    /// than to the voices, and reads as the quiet thing underneath them.
    ///
    /// Kajar was purple. That was fine while the voices were teal and indigo and
    /// stopped being fine the moment sangsih became purple too: a pulse dot and
    /// a stroke you are meant to play should never be one colour.
    static let gong = Color(hex: 0xF0DDA8)
    static let kempur = Color(hex: 0xD9A441)
    static let kajar = Color(hex: 0xA89478)

    // MARK: - The two interlocking halves (§7)

    /// Polos and sangsih keep their own colour wherever they appear, so the
    /// weave reads at a glance — the score, the picker cards, the mixer chips.
    ///
    /// Blue for polos, the steady half on the beat; purple for sangsih, which
    /// answers between. They were borrowed from the old rank ladder's colours
    /// to keep the number of separate accents down, and kept their values when
    /// the ranks went. Swapping the two is a one-line change if it reads better
    /// the other way round.
    static let polosVoice = Color(hex: 0x5FA8D3)
    static let sangsihVoice = Color(hex: 0xA97CD1)

    static let keyOutlineWidth: CGFloat = 3
    static let keyCornerRadius: CGFloat = 6
    /// Practice speeds, slowest first. 1× is the tempo the figure is notated
    /// at; below it is for getting a shape into the hands, above it is for
    /// proving it is actually there. 1.75× and 2× because a gangsa section
    /// really does play kotekan that fast — 1.5× stopped short of performance
    /// speed.
    static let tempoScales: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    /// "0.75×". Trailing zeroes trimmed — "1.0×" beside "0.75×" reads as a
    /// precision the setting does not have.
    static func tempoLabel(_ scale: Double) -> String {
        String(format: "%g×", scale)
    }

    // R The approach-track geometry lived here — strike line at 0.15, three
    // R seconds of lookahead, 0.8s of trail. All of it belonged to a score that
    // R scrolled. NotesRiver draws one still cycle now and has no lookahead to
    // R size: the whole figure is always on screen.
}

// MARK: - Typography

/// Resolves the bundled display face ONCE, by PostScript name.
///
/// `UIFont.fontNames(forFamilyName:)` is the wrong probe here and has cost this
/// app a typeface before: family lookup can come back empty for a bundled face
/// whose family the system has folded into an existing one, so the guard fails
/// and everything silently falls through to the system font without looking
/// broken enough to notice. `UIFont(name:size:)` asks about the exact face
/// instead, which is the thing we actually depend on.
enum KotekFonts {
    static let displayRegular: String? = [
        "Katibeh-Regular", "Katibeh"
    ].first { UIFont(name: $0, size: 12) != nil }

    /// What the app actually resolved, for the diagnostics screen — so "is the
    /// font loaded?" is answerable rather than eyeballed. Only the display face
    /// can fail now; the body face is San Francisco, which ships with the OS.
    static var summary: String {
        "display=\(displayRegular ?? "SYSTEM")  body=SF Pro"
    }
}

extension Font {
    /// Katibeh — the display face, for titles, headings and big numerals.
    ///
    /// One weight only, so `weight` is honoured by the system fallback alone.
    /// It replaced Dream Orphans, which shipped Regular and Bold.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard let name = KotekFonts.displayRegular else {
            return .system(size: size, weight: weight, design: .serif)
        }
        return .custom(name, size: size)
    }

    /// San Francisco — body, labels, buttons, everything that is not a heading.
    ///
    /// This was a bundled cut of Futura Medium Condensed. Two things came with
    /// that and are worth stating, because both are now fixed rather than
    /// worked around:
    ///
    ///  - It shipped in ONE weight, so `weight` could not be honoured and was
    ///    ignored outright; emphasis had to be faked with tracking and colour.
    ///    SF Pro has the full range, so every existing `weight:` argument in the
    ///    app starts doing what it always said it did.
    ///  - It is a geometric face with a small x-height, condensed on top. At the
    ///    11–14pt this app mostly uses — over a live camera image, read at
    ///    arm's length by someone holding a mallet — that is the worst possible
    ///    combination. SF is drawn for exactly this: its Text optical size opens
    ///    the spacing and thickens the stems below 20pt, and swaps to the
    ///    tighter Display cut above it, automatically and per size.
    ///
    /// The name stays `sans` rather than becoming `sf`: ~250 call sites say
    /// "the body face", which is still exactly what they mean.
    ///
    /// Never below 11pt — the smallest size the Human Interface Guidelines
    /// allow (Caption 2). A handful of labels were drawn at 9 and 10.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: max(11, size), weight: weight, design: .default)
    }

    /// A system font for SF Symbols, so glyphs take the symbol metrics rather
    /// than inheriting a text size that happens to be nearby.
    ///
    /// Symbols in the app used to be given `.font(.sans(...))`. Under Futura
    /// that meant a symbol scaled to a face with entirely unrelated metrics,
    /// which is why icons sat slightly high or small next to their labels.
    static func symbol(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Reusable text treatments

extension View {
    /// The uppercase, letter-spaced label used for section headers and eyebrows.
    func eyebrow(_ color: Color) -> some View {
        font(.sans(12))
            .textCase(.uppercase)
            .tracking(2.5)
            .foregroundStyle(color)
    }
}

extension Text {
    /// Convenience for a tracked uppercase eyebrow string.
    func trackedLabel() -> some View {
        textCase(.uppercase).tracking(2.5)
    }
}

// MARK: - Hex

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Model UI Color Extensions

extension JudgementResult {
    var color: Color {
        switch self {
        case .perfect: Theme.hit
        case .good: Theme.hit.opacity(0.8)
        case .lateEarly: Theme.upcoming
        case .miss: Theme.miss
        case .wrongKey: Theme.wrong
        }
    }
}

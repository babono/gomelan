//
//  Theme.swift
//  Kotek
//
//  The Kotek design system.
//
//  One surface, not two — that much has held since the October 2026 revamp,
//  which collapsed a cream "paper" world and an ink "stage" world into one
//  ground for every screen, with the camera screens simply the ones where a
//  live image covers it. What the November 2026 redesign changed is the
//  ground: it went from warm brown to paper, and the app from dark to light.
//
//  The palette is Nawa Sanga, the Balinese directions of the gods — the
//  colours students already know from canang sari offerings (the designer's
//  design system, November 2026). Every one is in the asset catalog under its
//  Balinese name, so the designers can change a colour without a code edit:
//
//    Merah      #E14B2F  courage — the one thing to tap next; polos
//    Kuning     #F5B331  reward — focus, a hit, what is selected
//    Ireng      #1E2435  calm focus — text; damp
//    Putih      #FBF6EE  a fresh start — the canvas
//    SangsihBlue #2F4B82 sangsih, never confused with polos
//    Pandan     #2E9A68  leaf green — sensor on, switches, "all good"
//    Kayu       #F2DDB4  warm wood — the bilah
//    MerahTua   #A93321  the tactile edge under the primary button
//    Krem       #F5EDE0  secondary surfaces — chips, quiet buttons
//    Garis      #CDBBA3  outlines, and the edge under a secondary button
//
//  Plus Surface (white: cards, outlined buttons, fields, Kipli's bubble),
//  PatternBackground (the gate silhouettes), DescriptionText (supporting
//  text) and BrandRed (the wordmark's own red, kept apart from Merah).
//
//  The rules that come with it: one red button per screen; gold means you did
//  well or this is selected; Kipli speaks in the outlined bubble; an 8pt grid
//  and 44pt touch targets.
//
//  The November redesign's first palette — orange #DF6D2F, gold #E7B142,
//  charcoal #2F2F2F — lasted one pass. Orange was the main action AND every
//  heading, so nothing stood out; Nawa Sanga moves headings to Ireng and
//  keeps the red for the way on.
//
//  Every control is SOLID — no Liquid Glass. Glass is iOS-only, and the app is
//  going to Android; a fill and an edge are the same on both. They are
//  TACTILE: each sits on a darker base a few points below it, and sinks onto
//  it while pressed. See `AppControlSurface`.
//
//  Type: Katibeh for titles and headings (the design system names Fraunces
//  Black; Katibeh stays for now) — bundled, see UIAppFonts in
//  Info.plist, and falling back to the nearest system serif if a build ever
//  ships without it. It comes in one weight. Everything else is SF Pro
//  Rounded, as the design system asks — San Francisco's own rounded cut, so
//  the optical sizes and every weight still come with it.
//
//  The old token NAMES are kept (`ink`, `cream`, `copper`, `terracotta` …)
//  because ~250 call sites use them and renaming would be a mechanical change
//  with no design value. What changed, three times now, is what they point at
//  — `cream` is body text, and body text is Ireng; `gold` is gold again.
//

import SwiftUI

enum Theme {
    // MARK: - Nawa Sanga

    static let merah = Color("Merah")
    static let kuning = Color("Kuning")
    static let ireng = Color("Ireng")
    static let putih = Color("Putih")
    static let sangsihBlue = Color("SangsihBlue")
    static let pandan = Color("Pandan")
    static let kayu = Color("Kayu")
    static let merahTua = Color("MerahTua")
    static let krem = Color("Krem")
    static let garis = Color("Garis")

    // MARK: - The three roles

    /// Merah. The screen's one way on, and polos.
    static let primary = merah
    /// Kuning. Reward and focus: a hit, a done step, what is selected.
    static let secondary = kuning
    /// Ireng. Text, the dark chip that is selected, and damp.
    static let tertiary = ireng

    // MARK: - Neutrals

    /// The ground. Every screen sits on this.
    static let ground = putih
    /// The gate silhouettes at the screen's sides — see `PatternBackground`.
    static let pattern = Color("PatternBackground")
    /// White: what is raised off the ground — a card, an outlined button, a
    /// field, Kipli's bubble.
    static let surface = Color("Surface")
    /// Quiet surfaces: chips, the stepper's buttons, a switcher's track.
    static let deep = krem
    /// Body text. Named for the colour it used to be.
    static let cream = ireng
    /// Selected, focused, done: gold. (The brown design's name, and its
    /// meaning again after a pass as the orange.)
    static let gold = kuning
    /// Gold as TYPE. Kuning itself is about 1.8:1 on Putih — a fill, a beam,
    /// a ring, never words — so a gold label is Kuning deepened with Ireng
    /// until it reads.
    static let goldText = kuning.mix(with: ireng, by: 0.45)
    /// Headings in Katibeh: Ireng, as the design system sets every title.
    static let heading = ireng
    /// The one heading that shouts — "Perfect!" on Results.
    static let feedback = merah
    /// Supporting text: descriptions, metadata, captions, eyebrows.
    static let description = Color("DescriptionText")
    /// Outlines: a control's edge, a divider, an idle key's outline.
    static let hairline = garis
    /// The wordmark's red. Not Merah: the logo is artwork, and keeps its own.
    static let brandRed = Color("BrandRed")
    /// A bilah as it is struck, on the landing screen's gangsa.
    static let keyHighlight = Color("KeyHighlight")
    /// A bilah the player's hand has just stopped ringing — see
    /// `GangsaTable`.
    static let keyDampened = Color("KeyDampened")
    /// A note's ring, from its stroke to where it is damped: a cream stem
    /// outlined in beige, capped in the beige. The waterfall draws it falling,
    /// Studio's piano roll lying down, so a note looks the same on both.
    static let stemCream = Color(hex: 0xF7EDDC)
    static let dampBeige = Color(hex: 0xE7DBC6)

    // MARK: - Status

    /// Connected, checked, all good: pandan.
    static let ok = pandan
    /// Still on its way — looking for sensors, connecting: gold.
    static let pending = kuning
    /// Something the player has to do something about.
    static let destructive = merahTua

    /// The launch screens' names for the same neutrals, from when the
    /// redesign covered launch alone.
    static let paper = ground
    static let paperPattern = pattern
    static let paperText = description
    /// The bilah on the drawn gangsa: gold, as the designer's gangsa draws
    /// them. (`kayu` is the bilah as a TILE — note capture.)
    static let bilah = kuning

    /// Struck bronze — the bilah themselves.
    static let bronze = Color(hex: 0xC9A876)

    // MARK: - Legacy names, repointed

    //
    // Kept so the call sites keep meaning what they meant: "the ground",
    // "a surface", "strong body text", "supporting text", "an accent".

    static let ink = ground
    static let inkRaised = surface
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

    /// Text for use ON a primary fill. Named for the job rather than the
    /// colour.
    static let onCream = onButtonFill

    // MARK: - Button colours

    //
    // Named for the JOB: `onButtonFill` is only correct on top of
    // `buttonFill`, and the pair has to move together or the label stops being
    // legible.

    /// The main action's fill: Merah.
    static let buttonFill = primary
    /// The main action's tactile edge: Merah tua.
    static let buttonBase = merahTua
    /// Type sitting on any filled action — white.
    static let onButtonFill = surface
    /// Every secondary control's fill: white, outlined in Garis.
    static let glassTint = surface
    /// Type on the main action.
    static let onGlassFill = onButtonFill

    // MARK: - Geometry

    /// Corner radius for buttons, cards and wells.
    static let radius: CGFloat = 14
    /// Space under a screen's bottom action bar, above the safe area. The
    /// footers had grown 2, 8, 10, 16 and 20 each, and the narrow ones sat
    /// cramped on the bottom edge — most visibly Results on iPad.
    static let footerBottom: CGFloat = 16
    /// Height of a primary button: what the system draws a `.large` AppButton
    /// at (`.extraLarge` control size, measured), so the one control that is not
    /// ours — Sign in with Apple — sits at the same height beside it.
    static let buttonHeight: CGFloat = 52

    // The header's one set of metrics (`headerBar()`), so the back button sits
    // at the same x and y on every screen. It was 24, 8, 40 and 0 from the edge
    // and 4, 6, 10, 12, 14 and 18 from the top, depending on who drew the bar.
    // 10 + 44 + 8 = 62: the play screens' old total (6 + 50 + 6), so the stage
    // under a bar does not resize.
    static let headerInset: CGFloat = 24
    static let headerTop: CGFloat = 10
    static let headerBottom: CGFloat = 8
    static let headerHeight: CGFloat = AppButtonSize.regular.height

    /// The main action's label weight, shared so the buttons cannot drift
    /// apart. Bold, in sentence case: "Next", as the redesign draws it. It was
    /// Black, uppercase and tracked ("NEXT") on the brown design.
    static let buttonWeight: Font.Weight = .bold

    // MARK: - Overlay play colours (§13.5)

    //
    // Nawa Sanga, as the design system assigns them: a hit is gold (reward),
    // a miss or a wrong key the deep red. Both used to be stock-ish — a hit
    // green, a miss the wordmark red — and with polos now Merah, a red miss
    // on a polos note would have read as the note itself.

    /// Almost: early or late enough to say so. Kayu — gold with the light
    /// gone out of it.
    static let upcoming = kayu
    static let hit = kuning
    static let miss = merahTua
    static let wrong = merahTua

    // MARK: - Colotomic layer (gong / kempur / kajar)

    /// One warm family — bronze, amber, stone. The colotomic layer frames the
    /// cycle rather than carrying a part, so it belongs to the ground rather
    /// than to the voices, and reads as the quiet thing underneath them.
    ///
    /// Kajar was purple. That was fine while the voices were teal and indigo and
    /// stopped being fine the moment sangsih became purple too: a pulse dot and
    /// a stroke you are meant to play should never be one colour.
    /// Dark bronze, not the brown design's cream: on paper the cream vanished.
    static let gong = Color(hex: 0x7B5F39)
    static let kempur = Color(hex: 0xD9A441)
    static let kajar = Color(hex: 0xA89478)

    // MARK: - The two interlocking halves (§7)

    /// Polos and sangsih keep their own colour wherever they appear, so the
    /// weave reads at a glance — the score, the picker cards, the mixer chips.
    ///
    /// Merah for polos, the steady half on the beat; Sangsih blue for the half
    /// that answers between — the design system's pair. They were sky blue and
    /// purple, borrowed from the old rank ladder's colours.
    static let polosVoice = merah
    static let sangsihVoice = sangsihBlue

    static let keyOutlineWidth: CGFloat = 3
    static let keyCornerRadius: CGFloat = 6
    /// Practice speeds, slowest first. 1× is the tempo the figure is notated
    /// at; below it is for getting a shape into the hands, above it is for
    /// proving it is actually there. 1.75× and 2× because a gangsa section
    /// really does play kotekan that fast — 1.5× stopped short of performance
    /// speed.
    static let tempoScales: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    /// "0.75×". Trailing zeroes trimmed — "1.0×" beside "0.75×" reads as a
    /// precision the setting does not have. Formatted, not `%g`, so the
    /// decimal mark follows the language: "0,75×" in Indonesian.
    /// Nonisolated so a menu can take it as its (nonisolated) title function.
    nonisolated static func tempoLabel(_ scale: Double) -> String {
        "\(scale.formatted(.number.precision(.fractionLength(0 ... 2))))×"
    }

    /// "77%" from 0.77, in the reader's own number style. A percent built by
    /// hand as `"\(n)%"` is right in English and wrong in languages that
    /// space or place the sign differently.
    nonisolated static func percentLabel(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
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
    ///
    /// Rounded since the Nawa Sanga design system ("SF Pro Rounded for
    /// everything you read and tap"): the same family, so all of the above
    /// still holds.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: max(11, size), weight: weight, design: .rounded)
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
    /// The small label over a section, in sentence case (see `SectionLabel`).
    func eyebrow(_ color: Color) -> some View {
        font(.sans(13, weight: .semibold))
            .foregroundStyle(color)
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

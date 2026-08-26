//
//  SplashView.swift
//  Kotek
//
//  The launch screen: the wordmark, a loading pill, the Mekar Bhuana credit
//  underneath, and who built it along the foot.
//
//  It is a progress screen, not a delay. Everything it waits on is real work
//  the app used to do later and more visibly — see `Preloader` — so the time
//  spent here is time the framing screen and the first session no longer spend
//  frozen. It does have a floor, but that floor is set by the credit: a
//  collaborator's name nobody has time to read is not a credit.
//
//  Nothing on it animates in. The wordmark is simply drawn, at exactly the size
//  and place the landing screen draws it, and the pill is the only thing that
//  moves. That is what makes the hand-over work: the landing screen fades up
//  around a mark that never moved and never changed.
//

import SwiftUI

struct SplashView: View {
    /// 0…1. Drives the pill.
    var progress: Double

    /// Who built it, along the foot.
    ///
    /// The same line the marketing site carries in its footer, set the same
    /// way: the academy is the part with weight behind it, so it and the mark
    /// beside it are the bright half and the words either side hold back.
    ///
    /// ONE `Text`, concatenated, rather than an `HStack` of four. The Apple
    /// mark has to sit on the baseline of the words around it and scale with
    /// them under Dynamic Type — an image in a stack is a box beside the type
    /// that does neither, and lining it up by eye means re-lining it up at
    /// every text size.
    ///
    /// It belongs on THIS screen rather than the landing one. It is about 370pt
    /// of type at this size, and the landing screen has nowhere to put a line
    /// that long: the top corner is where the wordmark's ink starts, and the
    /// foot is the instrument, which runs off the bottom edge by design. Here
    /// it is one more line in a column of credits, on the one screen whose
    /// duration is set by how long its text takes to read.
    private var builtAt: some View {
        (
            Text("Built at  ").foregroundStyle(Theme.cream.opacity(0.5))
            + Text(Image(systemName: "apple.logo")).foregroundStyle(Theme.cream.opacity(0.82))
            + Text("  Apple Developer Academy Bali  ").foregroundStyle(Theme.cream.opacity(0.82))
            + Text("for the gamelan community.").foregroundStyle(Theme.cream.opacity(0.5))
        )
        .font(.sans(12))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        //R VoiceOver cannot read an inline symbol, and "Built at  Apple
        //R Developer Academy Bali" with a picture in the middle of it is a
        //R sentence with a hole. Stated once, as a sentence.
        .accessibilityLabel("Built at Apple Developer Academy Bali, for the gamelan community")
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                Theme.ground.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer().frame(height: KotekWordmark.topInset(in: h))

                    KotekWordmark(width: KotekWordmark.width(in: w))

                    //R Tightened from 0.10 / 0.09 / 0.035 when the Sanskrit
                    //R mark went under the wordmark. On a landscape 15 Pro the
                    //R column had ~44pt of slack left and the script needs more
                    //R than that; every item below here is sized from the
                    //R WIDTH, so a wide short screen is where this overflows
                    //R first and the one to check against.
                    Spacer().frame(height: h * 0.06)

                    ProgressPill(progress: progress)
                        .frame(width: min(280, w * 0.32), height: min(38, h * 0.10))

                    Spacer().frame(height: h * 0.05)

                    Text("in collaboration with")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Theme.cream.opacity(0.72))

                    Spacer().frame(height: h * 0.03)

                    Image("logo-mekarbhuana")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        //R Taken down from 320 / 0.36. It is the second credit
                        //R on the screen now rather than the last thing on it,
                        //R and at the old size it out-weighed the wordmark it
                        //R sits under.
                        .frame(width: min(260, w * 0.29))

                    //R The slack in the column collects HERE, between the two
                    //R credits, so the built-at line sits a fixed distance off
                    //R the bottom edge on every screen while the block above it
                    //R stays packed under the wordmark.
                    Spacer(minLength: 0)

                    builtAt

                    Spacer().frame(height: h * 0.06)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Progress pill

/// The loading bar from the design: a cream track that a deeper gold fills
/// across, with the percentage read out in the middle of it.
///
/// The track is `Theme.buttonFill` — the same #FDDC8A slab every primary button
/// in the app is made of — so the type on it is `Theme.onButtonFill`, the token
/// named for exactly that job. The pill is the one place the app shows that
/// surface before you have anything to press.
///
/// It used to run the other way: a tan track that a DARK fill swept across, so
/// the bar emptied of tan rather than filling with it. That inversion cost the
/// readout a double draw — dark type vanished into the dark fill and light type
/// vanished into the light track, so the number was painted twice and clipped
/// to the boundary, inverting digit by digit as the fill crossed them. With
/// both halves of the bar light, one dark readout reads on both and all of that
/// machinery goes. If the palette ever inverts again, that is the trick to
/// bring back.
private struct ProgressPill: View {
    var progress: Double

    /// The gutter between the fill and the track around it.
    private let inset: CGFloat = 3

    /// The swept portion. The one colour in the app that exists only here — a
    /// gold deep enough to read against #FDDC8A without becoming a second
    /// accent, which `Theme.gold` at #C9A063 was too close to the track to do.
    private let sweep = Color(hex: 0xBF9145)

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let clamped = min(1, max(0, progress))
            // Never narrower than its own height: below that a capsule collapses
            // into a lens shape and the bar looks broken at rest rather empty.
            let fillWidth = max(size.height - inset * 2,
                                (size.width - inset * 2) * clamped)

            ZStack(alignment: .leading) {
                Capsule().fill(Theme.buttonFill)

                fill(width: fillWidth, in: size)
                    .foregroundStyle(sweep)

                //R One draw, one colour. See the note above the type: dark
                //R reads on the track AND on the sweep now, so the number no
                //R longer has to invert as the boundary crosses it.
                readout
                    .foregroundStyle(Theme.onButtonFill)
                    .frame(width: size.width, height: size.height)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }

    /// The swept portion.
    private func fill(width: CGFloat, in size: CGSize) -> some View {
        Capsule()
            .frame(width: width, height: size.height - inset * 2)
            .offset(x: inset)
    }

    private var readout: some View { Readout(value: progress) }
}

/// The percentage itself, counting rather than jumping.
///
/// `Animatable` is the whole point of this being its own type. Progress lands in
/// three steps as each preload task finishes, and the bar glides between them
/// because `withAnimation` interpolates its width — but a plain `Text` would
/// re-render only at the steps, so the number would snap 0, 35, 70, 100 while
/// the bar slid smoothly underneath it. Two things reporting one value, visibly
/// disagreeing. Exposing the value as `animatableData` makes SwiftUI re-evaluate
/// this body at every frame of the same animation, so the digits count up with
/// the fill they sit on.
private struct Readout: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        // Monospaced digits so the number does not jitter as it counts: with
        // proportional figures the text shuffles sideways on nearly every
        // change, which is very visible on something otherwise this still.
        // Clamped here rather than by the caller: `animatableData` is fed
        // interpolated values, and an animation curve that overshoots would
        // otherwise briefly read 101%.
        Text(min(1, max(0, value)), format: .percent.precision(.fractionLength(0)))
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .tracking(0.5)
            // Decoration over the bar it duplicates; the pill already carries
            // the accessibility value, and two readings of one number is noise.
            .accessibilityHidden(true)
    }
}

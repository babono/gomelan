//
//  OnboardingView.swift
//  Kotek
//
//  The introduction: three full-screen slides, shown unasked exactly once on a
//  first run and after that only when somebody asks for it again from the help
//  button on the instrument picker. See `AppState.showingOnboarding`.
//
//  It took over from the "How Kotek works" panel that used to appear over the
//  instrument picker on a first run. That was a two-column reference sheet
//  arriving before anybody had done anything, in a dimmed overlay with a Got it
//  in the corner — the shape of something to dismiss rather than something to
//  read. This is the whole screen, one idea per slide, and the way out is the
//  same forward button you have been pressing since the splash.
//
//  It did not take the whole of it. That panel still exists over the instrument
//  picker, having changed subject: what a gangsa IS, that it is the only
//  instrument Kotek reads, and what the grade on each card means. Those are
//  questions that screen raises, and none of them belong in an introduction
//  shown before anybody has chosen anything. See `GuideView`.
//
//  Full-screen, so it paints its OWN ground: the pattern in `RootView` is
//  behind the app, and this sits over it. A second `PatternBackground` means a
//  second drift phase, which would be visible if the two were ever on screen
//  together — they never are, because this covers the screen edge to edge.
//
//  LANDSCAPE, like everything else: a picture beside a column of type, never
//  stacked. The phone gives about 390pt of height and 850 of width, so a slide
//  that stacks its art over its title has room for neither.
//
//  The slides are hand-built rather than driven off a `[Slide]` array. Each one
//  animates differently — a rotating mark, two Lottie files, a still — and the
//  data-driven version was a struct with one optional per slide type plus a
//  switch to unpack it again, which is the same code with an extra hop.
//

import SwiftUI
import Lottie

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var index = 0

    private static let slideCount = 3

    var body: some View {
        ZStack {
            //R Its own ground. See the file header — this is over the app, not
            //R in it, and the pattern behind it is not visible through it.
            PatternBackground()

            TabView(selection: $index) {
                WelcomeSlide(onNext: next).tag(0)
                InterlockSlide(onNext: next).tag(1)
                TrackingSlide(onFinish: finish).tag(2)
            }
            //R Our own dots, drawn over the pager rather than inside it. The
            //R system's claim a strip of the page's own height and are a
            //R blue-grey nothing on a warm ground. Same reasoning, and the same
            //R drawing, as `GuideSlides`.
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                Spacer()
                dots.padding(.bottom, 10)
            }
        }
        //R NO `ignoresSafeArea` here. `PatternBackground` applies its own, so
        //R the ground reaches the edges, while the slides stay inside the
        //R insets — in landscape the sensor housing is on the leading edge,
        //R which is exactly where two of the three slides put their artwork.
        .transition(.opacity)
    }

    private func next() {
        withAnimation(.snappy(duration: 0.3)) { index = min(index + 1, Self.slideCount - 1) }
    }

    private func finish() {
        withAnimation(.easeInOut(duration: 0.3)) { onFinish() }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<Self.slideCount, id: \.self) { i in
                Button { withAnimation(.snappy(duration: 0.25)) { index = i } } label: {
                    Circle()
                        .fill(i == index ? Theme.buttonFill : Theme.cream.opacity(0.22))
                        .frame(width: 7, height: 7)
                        //R Drawn at 7pt and hit at 30. A row of seven-point
                        //R targets is a row of near-misses.
                        .frame(width: 30, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.kajar)
                .accessibilityLabel("Slide \(i + 1) of \(Self.slideCount)")
            }
        }
        .frame(height: 26)
    }
}

// MARK: - The shared slide shell

/// A slide is a picture and a column of type, side by side, and which side the
/// picture takes is the only thing that varies. Held in one place so the type
/// column cannot drift between slides — it is the same title, the same lead and
/// the same button on all three, and three copies of that is three chances for
/// one of them to end up a point off.
private struct SlideLayout<Art: View, Action: View>: View {
    enum ArtSide { case leading, trailing }

    var artSide: ArtSide = .leading
    /// The title, set on two lines: the first in cream, the second in gold.
    /// Two `Text`s rather than one with a line break, because the colour change
    /// is the point — it is what makes the second line the subject.
    let titleTop: String
    let titleBottom: String
    /// Markdown, so a slide can put **polos** in bold without a second view.
    let lead: LocalizedStringKey
    @ViewBuilder var art: Art
    @ViewBuilder var action: Action

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height

            HStack(spacing: 28) {
                if artSide == .leading { artColumn }
                textColumn(height: h)
                if artSide == .trailing { artColumn }
            }
            .padding(.horizontal, 44)
            //R Bottom padding clears the dots; top matches it so the row still
            //R sits on the optical centre rather than riding high.
            .padding(.top, 36)
            .padding(.bottom, 36)
        }
    }

    private var artColumn: some View {
        //R The art is painted INTO a `Color.clear` rather than framed. A
        //R resizable image negotiates its own size from its aspect ratio, so a
        //R tall picture in a wide slot demands more height than the row has and
        //R pushes the type column past the bottom of the screen. `Color.clear`
        //R takes whatever it is offered — see the same trick in `GuideSlides`.
        Color.clear
            .overlay { art }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private func textColumn(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            //R Sized off the container, not typed in. These are the largest
            //R words in the app and the difference between a 4.7" phone and an
            //R iPad is more than a `minimumScaleFactor` can absorb gracefully.
            let titleSize = min(52, max(30, height * 0.13))

            //R The titles never wrap: they are one or two words each, and a
            //R wrapped title is a copy problem rather than a layout one. The
            //R scale factor is the backstop for large Dynamic Type.
            Group {
                Text(titleTop).foregroundStyle(Theme.cream)
                Text(titleBottom).foregroundStyle(Theme.buttonFill)
            }
            .font(.serif(titleSize))
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            Text(lead)
                .font(.sans(16))
                .foregroundStyle(Theme.cream.opacity(0.78))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            action.padding(.top, 22)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The three slides

private struct WelcomeSlide: View {
    var onNext: () -> Void

    var body: some View {
        SlideLayout(artSide: .leading,
                    titleTop: "Welcome to",
                    titleBottom: "Kotek",
                    lead: "Reimagining Balinese heritage through interactive play.") {
            SpinningMark()
        } action: {
            PillButton(title: "Next", trailingSystemImage: "arrow.right",
                       style: .filled, action: onNext)
        }
    }
}

private struct InterlockSlide: View {
    var onNext: () -> Void

    var body: some View {
        SlideLayout(artSide: .leading,
                    titleTop: "Master the",
                    titleBottom: "Interlock",
                    lead: "Learn to play the **Polos** and **Sangsih** parts that form the core of gamelan rhythm.") {
            //R Two gangsa, one above the other, because that is what the pair
            //R IS — two players at two instruments, not one animation with two
            //R mallets in it.
            VStack(spacing: 10) {
                DotLottieArt(name: "polos")
                DotLottieArt(name: "sangsih")
            }
        } action: {
            PillButton(title: "Next", trailingSystemImage: "arrow.right",
                       style: .filled, action: onNext)
        }
    }
}

private struct TrackingSlide: View {
    var onFinish: () -> Void

    var body: some View {
        //R The one slide with the art on the RIGHT. It is the last, and the
        //R mirrored layout is what says so — the deck opens with a picture and
        //R closes with the words on the same side as the button you press.
        SlideLayout(artSide: .trailing,
                    titleTop: "Precision",
                    titleBottom: "Tracking",
                    lead: "Use your **camera** to get real-time feedback on your technique and timing.") {
            Image("precision-tracking")
                .resizable()
                .aspectRatio(contentMode: .fit)
        } action: {
            PillButton(title: "Finish", style: .filled, action: onFinish)
        }
    }
}

// MARK: - The artwork

/// The mallet pinwheel, turning.
///
/// One `repeatForever` rotation driven by Core Animation, not a
/// `TimelineView`: the mark is a single static image and the whole animation is
/// a transform, so the render server can interpolate it and the app process
/// does no work per frame. Same reasoning as `PatternBackground` — see its
/// header for what the 30fps version of that cost.
private struct SpinningMark: View {
    @State private var turning = false

    /// Slow. It is a mark being present, not a spinner reporting work: a full
    /// turn takes a bar of gong cycle rather than the second a loading
    /// indicator would take, and at that rate the eye reads it as drifting.
    private static let period: Double = 24

    var body: some View {
        Image("icon-kotek")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(.linear(duration: Self.period).repeatForever(autoreverses: false),
                       value: turning)
            .onAppear { turning = true }
            .padding(12)
    }
}

/// One dotLottie file, looping.
///
/// Loaded through the async initialiser rather than the synchronous one:
/// `DotLottieFile` is a zip holding a JSON and several PNGs, and these two are
/// about a megabyte each. Unpacking that on the main thread stalls the slide
/// it is meant to appear on. The placeholder is nothing at all — a spinner over
/// a slide somebody is reading is worse than a picture that arrives a beat
/// late.
private struct DotLottieArt: View {
    let name: String

    var body: some View {
        LottieView { try await DotLottieFile.named(name) }
            .resizable()
            .looping()
            //R Off-screen slides keep their place in the loop rather than
            //R restarting when you page back. Paging back to a figure that
            //R jumps to frame zero reads as a glitch.
            .backgroundBehavior(.pauseAndRestore)
    }
}

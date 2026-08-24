//
//  ChooseKotekanView.swift
//  Kotek
//
//  Pick the interlocking figure to learn. Tapping the focused card goes straight
//  to the count-in — this is the last decision before playing, and the only one
//  left: which half you take is a toggle on the practice screen, and how many
//  times around has no answer, because it goes around until you stop it.
//
//  A LOOPING CAROUSEL THAT PLAYS WHAT IT IS SHOWING. It used to be four static
//  cards side by side, each offering a name, a level and a sentence of prose —
//  which tells a beginner nothing whatsoever about the thing they are choosing.
//  Kotekan is taught by imitation (*maguru panggul*): you hear the figure, then
//  you copy it. So the picker sounds the focused figure and draws both halves
//  against the gong underneath it, and swiping is how you audition the set.
//
//  Borrowed from the arcade music-select wheel, minus the wheel. The behaviour
//  is the good part — always exactly one thing focused, always previewing, no
//  end to swipe off — and the spinning disc rack is not: this app has one warm
//  ground and no ornament that competes with content, and a rack of records
//  would be the loudest thing in it.
//
//  The score lives INSIDE the card, not in a strip along the bottom. Nobody
//  should be settling in here: a full-width score at the foot of the screen
//  gives the picker content of its own and makes it somewhere to stay, when the
//  whole job is to get you to an instrument with a mallet in your hand. Folded
//  into the card it is part of the thing being chosen — and every card can
//  carry one, playing or not, so the whole set can be compared by shape at a
//  glance. That is also why the cards lost their blurb: the shape says more
//  about a kotekan than a sentence about it does, and it says it faster.
//
//  Figures that need more bilah than the calibrated gangsa has can still be
//  swiped to and heard; they simply cannot be started. Hearing what you are
//  missing is a better reason to go and re-align than a greyed-out card.
//

import SwiftUI

struct ChooseKotekanView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    let cue: CuePlayer

    @State private var engine = PlayEngine()
    @State private var displayLink = DisplayLink()
    /// Which SLOT is centred, as a continuous unbounded number.
    ///
    /// Not an index and not wrapped. A wrapped index has to renumber every card
    /// the moment focus moves, and a card that is renumbered is a card SwiftUI
    /// throws away and rebuilds — so the snap could only ever cross-fade
    /// between two arrangements instead of sliding between them. Slot 5 is
    /// simply the figure at `wrap(5)`, one place right of slot 4, forever: the
    /// identity of what is on screen never changes, so moving `position` moves
    /// the cards.
    @State private var position: Double = 0
    /// Where `position` was when the current drag began.
    @State private var dragOrigin: Double?
    @State private var muted = false

    //R Sized so the neighbours reach the glass. On a landscape phone the rail
    //R has about 437 points either side of centre, and a card one slot out ends
    //R at half a card past one step — so a step of 294 puts its outer edge at
    //R 431, which is the edge for all practical purposes. At 250/20 it stopped
    //R 42 points short on both sides and the three cards read as three cards
    //R floating on a screen rather than as a piece of a rail.
    private let cardWidth: CGFloat = 272
    private let cardHeight: CGFloat = 178
    private let gap: CGFloat = 22

    private var step: CGFloat { cardWidth + gap }
    private var kotekans: [Kotekan] { app.kotekans }
    /// The centred slot, and the figure sitting in it.
    private var focusedSlot: Int { Int(position.rounded()) }
    private var current: Kotekan? {
        kotekans.isEmpty ? nil : kotekans[wrap(focusedSlot)]
    }
    private var playable: Bool {
        guard let current else { return false }
        return app.kotekan(current, playableOn: app.profile)
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Choose your kotekan",
                   onBack: { app.openChooseInstrument() },
                   settingsAction: { app.openSettings() },
                   infoAction: { app.openGuide(.kotekan) })

            carousel
                .frame(maxHeight: .infinity)
                //R The rail runs the full WIDTH of the glass, under the island
                //R and past both rounded corners. A carousel that stops at the
                //R safe area reads as a component sitting on a screen; one that
                //R runs off both edges reads as a rail you are looking at part
                //R of, which is the whole idea — there is no end to swipe off.
                //R
                //R Horizontal only. The bar and the footer keep their insets,
                //R because a title under the island is a title nobody can read.
                .ignoresSafeArea(.container, edges: .horizontal)

            footer
        }
        .onAppear {
            //R The second explainer, and it belongs HERE rather than folded into
            //R the first: "what am I choosing between" is a question you only
            //R have once you are looking at the choice.
            app.showGuideIfFirstRun(.kotekan)
            startPreview()
        }
        .onDisappear { stopPreview() }
        //R Keyed on the WRAPPED index: slot 4 and slot 0 are the same figure on
        //R a four-figure rail, and going round should not restart what is
        //R already playing.
        .onChange(of: wrap(focusedSlot)) { _, _ in startPreview() }
        //R Leaving the app must take the preview with it. Backgrounded, iOS
        //R pulls the audio session and stops the engine underneath us — and the
        //R display link comes back before anything says so, which is how a cue
        //R ends up calling play() on a dead node. `CuePlayer.ensureLive` is the
        //R backstop; this is not doing it in the first place.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { startPreview() } else { stopPreview() }
        }
        .onChange(of: muted) { _, isMuted in
            engine.partnerAudible = !isMuted
            engine.yourVoiceAudible = !isMuted
            if isMuted { cue.stopKeySamples() }
        }
    }

    // MARK: - The carousel

    /// Every figure is drawn TWICE, at `d` and at `d - n`.
    ///
    /// A wrapped index has one position, and one position leaves a hole: with
    /// four figures the one two places to the right is also the one two places
    /// to the left, and whichever way you resolve that, dragging the other way
    /// exposes empty space where a card should be coming in. Two copies each is
    /// eight views for four figures, most of them off-screen and clipped, and
    /// the seam disappears in both directions.
    private var carousel: some View {
        GeometryReader { geo in
            //R Two slots of margin each side. A card is 250 wide on a rail with
            //R about 440 points of half-screen, so anything two slots out is
            //R fully off the edge — which is where views should be entering and
            //R leaving, since that is the one place a transition cannot be seen.
            let first = Int((position - 2).rounded(.down))
            let last = Int((position + 2).rounded(.up))

            ZStack {
                ForEach(first...last, id: \.self) { slot in
                    let offset = Double(slot) - position
                    card(kotekans[wrap(slot)],
                         isPlaying: slot == focusedSlot,
                         offset: offset)
                        .position(x: geo.size.width / 2 + CGFloat(offset) * step,
                                  y: geo.size.height / 2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(swipe(width: geo.size.width))
        }
        .clipped()
    }

    /// ONE gesture for the whole rail — drag and tap both.
    ///
    /// Lowering `minimumDistance` did nothing, because the threshold was never
    /// the reason it felt like the swipe had to be earned. The cards each had
    /// their own `onTapGesture`, and a child gesture outranks a parent one in
    /// SwiftUI: the drag could not begin until the taps had been given a chance
    /// to lose, and that arbitration is the hesitation. There is nothing to
    /// arbitrate now — the rail tracks from the first frame, and a touch that
    /// never travelled is treated as a tap at the end of it.
    private func swipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                //R Captured once, so the whole gesture is measured from where it
                //R started rather than accumulating rounding on every callback.
                let origin = dragOrigin ?? position
                dragOrigin = origin
                position = origin - value.translation.width / step
            }
            .onEnded { value in
                let origin = dragOrigin ?? position
                dragOrigin = nil

                // A touch that went nowhere is a tap on whatever was under it.
                guard abs(value.translation.width) >= 10 else {
                    position = origin
                    tap(slotUnder(x: value.startLocation.x, width: width, origin: origin))
                    return
                }

                // Predicted, not actual: a flick that ends after 40pt but is
                // still travelling should advance, and a slow drag of the same
                // distance should not.
                let landing = origin - value.predictedEndTranslation.width / step
                withAnimation(.snappy(duration: 0.32)) {
                    //R Never more than one card per gesture. A hard flick
                    //R computes a landing four slots away, and four figures in
                    //R a blur is not an audition — the preview cannot even keep
                    //R up with it.
                    position = (landing.rounded()).clamped(to: origin - 1, origin + 1)
                }
            }
    }

    /// Which slot sits under a point on the rail. The inverse of the `.position`
    /// the cards are laid out with, so the two cannot disagree about what was
    /// tapped.
    private func slotUnder(x: CGFloat, width: CGFloat, origin: Double) -> Int {
        Int((Double(x - width / 2) / Double(step) + origin).rounded())
    }

    private func tap(_ slot: Int) {
        if slot == focusedSlot {
            let k = kotekans[wrap(slot)]
            if app.kotekan(k, playableOn: app.profile) { start(k) }
        } else {
            withAnimation(.snappy(duration: 0.32)) { position = Double(slot) }
        }
    }

    private func wrap(_ i: Int) -> Int {
        let n = kotekans.count
        return ((i % n) + n) % n
    }

    private func card(_ k: Kotekan, isPlaying: Bool, offset: Double) -> some View {
        // How focused this card is, 0…1. Taken from the same continuous
        // `position` the layout is, so the neighbour grows as it arrives — under
        // the finger during a drag and through the snap afterwards, with no
        // separate animation to keep in step.
        let nearness: CGFloat = max(0, 1 - min(abs(CGFloat(offset)), 1.6) / 1.6)
        let canPlay: Bool = app.kotekan(k, playableOn: app.profile)

        return cardBody(k, canPlay: canPlay, isPlaying: isPlaying)
            .padding(18)
            .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
            .background(Theme.deep.opacity(0.55 + 0.3 * nearness),
                        in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Theme.buttonFill.opacity(nearness),
                                  lineWidth: 1 + nearness)
            )
            // The neighbours are smaller and dimmer, which is what makes the
            // focused one read as focused without a highlight fighting the card
            // behind it.
            .scaleEffect(0.84 + 0.16 * nearness)
            .opacity(0.35 + 0.65 * nearness)
            //R No tap gesture here on purpose. See `swipe(width:)`.
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func cardBody(_ k: Kotekan, canPlay: Bool, isPlaying: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel("Level \(k.level) · \(k.toneLabel)", color: Theme.terracotta)

            Text(k.name)
                .font(.serif(26))
                .foregroundStyle(Theme.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            //R The playhead only on the card that is sounding. A sweep on a card
            //R you cannot hear would be claiming something untrue about which
            //R figure is playing.
            //R
            //R Keyed on the SLOT being the centred one, not on how near the
            //R card has drifted: which card owns the engine must not flicker
            //R part-way through a gesture.
            KotekanMiniScore(kotekan: k, engine: isPlaying ? engine : nil)
                .frame(height: 54)
                .padding(.top, 2)

            Spacer(minLength: 4)

            cardFoot(k, canPlay: canPlay)
        }
    }

    @ViewBuilder
    private func cardFoot(_ k: Kotekan, canPlay: Bool) -> some View {
        if !canPlay {
            Label("Needs \(k.requiredKeys) keys", systemImage: "lock")
                .font(.sans(12, weight: .medium))
                .foregroundStyle(Theme.miss)
        } else if let record = app.profile.bestRecord(kotekanId: k.id) {
            HStack(spacing: 6) {
                Image(systemName: "trophy").font(.symbol(11, weight: .semibold))
                Text(String(format: "%.0f%%", record.accuracy * 100))
                    .font(.sans(13, weight: .semibold))
                Text("\(record.half.capitalized) · \(Theme.tempoLabel(record.tempo))")
                    .font(.sans(12))
                    .foregroundStyle(Theme.cream.opacity(0.45))
            }
            .foregroundStyle(Theme.terracotta)
        }
    }

    // MARK: - Chrome

    private var footer: some View {
        HStack(spacing: 14) {
            Button { muted.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.symbol(13, weight: .semibold))
                    Text(muted ? "Muted" : "Playing")
                        .font(.sans(13, weight: .medium))
                }
                .foregroundStyle(muted ? Theme.cream.opacity(0.5) : Theme.gold)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .overlay(Capsule().strokeBorder(Theme.cream.opacity(0.22), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(muted ? "Unmute the preview" : "Mute the preview")

            Spacer()

            Text("Swipe to hear another")
                .font(.sans(13))
                .foregroundStyle(Theme.cream.opacity(0.45))

            Spacer()

            if let current {
                PillButton(title: "Start", trailingSystemImage: "arrow.right", style: .filled, compact: true) { start(current) }
                    .disabled(!playable)
                    .opacity(playable ? 1 : 0.4)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 10)
    }

    // MARK: - Preview

    /// Sound and draw the focused figure, from the top of its cycle.
    ///
    /// Re-entered on every swipe. `configure` resets the engine's clock state
    /// but not `startHostTime`, so `start()` is what actually re-zeros the
    /// cycle — without it a figure would come in halfway through itself.
    private func startPreview() {
        guard let k = current else { return }
        engine.cue = cue
        engine.metronomeEnabled = false
        engine.partnerAudible = !muted
        engine.yourVoiceAudible = !muted
        engine.configure(song: k.makeSong(half: .polos, cycles: 1),
                         partner: k.makeSong(half: .sangsih, cycles: 1),
                         profile: app.profile,
                         tempoScale: 1,
                         judging: false,
                         countIn: false)
        engine.start()
        displayLink.onFrame = { now in engine.tick(now: now) }
        displayLink.start()
    }

    private func stopPreview() {
        displayLink.stop()
        cue.stop()
    }

    private func start(_ k: Kotekan) {
        stopPreview()
        app.chooseKotekan(k)
    }
}

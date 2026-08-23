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
    let cue: CuePlayer

    @State private var engine = PlayEngine()
    @State private var displayLink = DisplayLink()
    @State private var focused = 0
    @State private var drag: CGFloat = 0
    @State private var muted = false

    private let cardWidth: CGFloat = 250
    private let cardHeight: CGFloat = 178
    private let gap: CGFloat = 20

    private var step: CGFloat { cardWidth + gap }
    private var kotekans: [Kotekan] { app.kotekans }
    private var current: Kotekan? {
        kotekans.indices.contains(focused) ? kotekans[focused] : kotekans.first
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
                   infoAction: { app.openGuide() })

            carousel
                .frame(maxHeight: .infinity)

            footer
        }
        .onAppear { startPreview() }
        .onDisappear { stopPreview() }
        .onChange(of: focused) { _, _ in startPreview() }
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
            ZStack {
                ForEach(kotekans.indices, id: \.self) { i in
                    let base = ((i - focused) % kotekans.count + kotekans.count) % kotekans.count
                    ForEach([base, base - kotekans.count], id: \.self) { d in
                        //R Two positions each, and most of them off the edge —
                        //R so only build the ones that can actually be seen.
                        //R Everything past a card and a half out is clipped
                        //R anyway, and a view that is never visible is still a
                        //R view SwiftUI has to diff on every touch move.
                        if abs(CGFloat(d) + drag / step) < 1.9 {
                            card(kotekans[i], isPlaying: i == focused, distance: CGFloat(d))
                                .position(x: geo.size.width / 2 + CGFloat(d) * step + drag,
                                          y: geo.size.height / 2)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(swipe)
        }
        .clipped()
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { drag = $0.translation.width }
            .onEnded { value in
                // Predicted, not actual: a flick that ends after 40pt but is
                // still travelling should advance, and a slow drag of the same
                // distance should not.
                let moved = -value.predictedEndTranslation.width / step
                let by = Int(moved.rounded())
                withAnimation(.snappy(duration: 0.3)) {
                    focused = wrap(focused + by)
                    drag = 0
                }
            }
    }

    private func wrap(_ i: Int) -> Int {
        let n = kotekans.count
        return ((i % n) + n) % n
    }

    private func card(_ k: Kotekan, isPlaying: Bool, distance d: CGFloat) -> some View {
        // How focused this card is, 0…1, following the drag so the neighbour
        // grows as it arrives rather than snapping when the gesture ends.
        let offset: CGFloat = d + drag / step
        let nearness: CGFloat = max(0, 1 - min(abs(offset), 1.6) / 1.6)
        let isFocused: Bool = abs(offset) < 0.5
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
            .onTapGesture {
                if isFocused {
                    if canPlay { start(k) }
                } else {
                    withAnimation(.snappy(duration: 0.3)) {
                        focused = wrap(focused + Int(offset.rounded()))
                    }
                }
            }
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
            //R `isPlaying` is index equality, not the drag-derived `isFocused`:
            //R it must not flicker mid-swipe, and it must not make this depend
            //R on the gesture.
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
                PillButton(title: "Start", style: .filled, compact: true) { start(current) }
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

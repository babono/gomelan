//
//  KotekanGuideView.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//
//  "How kotekan works" (.kotekan guide): three Krem cards, Polos, Sangsih and
//  Together, each drawing the same short sample and playing it on the
//  player's own gangsa — the designer's November 2026 card layout, with Kipli
//  saying the one-line idea above them.
//
//  It was two columns of prose (one melody, polos, sangsih; then a legend for
//  reading a picker card). Nobody hears an interlock from a paragraph, and the
//  legend described a card the redesign no longer draws.
//
//  The mockup drew each half as a row of squares, the other half's slots as
//  empty white outlines. Here every card draws the sample on its bilah, both
//  halves in their own voice colour: the half the card is about solid, the
//  other a dashed ghost in its colour, so the gaps one half leaves are seen
//  being filled by the other, and Together is the two woven into one line.
//

import FactoryKit
import SwiftUI

struct KotekanGuideView: View {
    /// Which card is sounding, and the slot it is on.
    @State private var hearing: GuideVoice?
    @State private var slot: Int?

    private let cue: CuePlayer = Container.shared.cueService()

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(GuideVoice.allCases) { voice in
                card(voice)
            }
        }
        // Closing the guide mid-sample stops it.
        .task(id: hearing) { await play(hearing) }
    }

    private func card(_ voice: GuideVoice) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(voice.title)
                .font(.serif(26))
                .foregroundStyle(Theme.heading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(voice.gloss)
                .font(.sans(14))
                .foregroundStyle(Theme.description)
                .fixedSize(horizontal: false, vertical: true)

            KotekanSampleRoll(voice: voice, slot: hearing == voice ? slot : nil)
                // Gives way first on a short phone, so the panel fits
                // without scrolling.
                .frame(minHeight: 36, maxHeight: 72)
                .frame(maxHeight: .infinity)

            hearButton(voice)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.deep, in: RoundedRectangle(cornerRadius: 22))
    }

    private func hearButton(_ voice: GuideVoice) -> some View {
        let on = hearing == voice
        return Button {
            KajarTick.strike()
            hearing = on ? nil : voice
        } label: {
            Label {
                Text(on ? "Stop" : voice.hear)
            } icon: {
                Image(systemName: on ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                    .symbolEffect(.variableColor.iterative, isActive: on)
            }
            .font(.sans(17, weight: .semibold))
            .foregroundStyle(Theme.merahTua)
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.appPlain)
    }

    /// The sample twice round, slot by slot, on the bundled or recorded key
    /// sounds; polos to the left and sangsih to the right, as the picker
    /// pans them.
    ///
    /// ponytail: `Task.sleep` for the clock rather than the PlayEngine. It is
    /// a few milliseconds loose, which a two-second demo does not show; the
    /// engine would bring a display link, a song and a colotomic frame to
    /// play eight strokes.
    private func play(_ voice: GuideVoice?) async {
        slot = nil
        guard let voice else { return }
        cue.start()
        for step in 0 ..< KotekanSample.slots * 2 {
            let s = step % KotekanSample.slots
            slot = s
            for half in voice.halves {
                if let key = KotekanSample.key(half, at: s) {
                    cue.playKeySample(index: key, pan: half == .polos ? -0.3 : 0.3, volume: 0.8)
                }
            }
            do { try await Task.sleep(for: .milliseconds(KotekanSample.strokeMs)) } catch { return }
        }
        slot = nil
        hearing = nil
    }
}

/// One card: a half on its own, or both.
enum GuideVoice: CaseIterable, Identifiable {
    case polos, sangsih, together

    var id: Self {
        self
    }

    var halves: [KotekanHalf] {
        switch self {
        case .polos: [.polos]
        case .sangsih: [.sangsih]
        case .together: [.polos, .sangsih]
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .polos: "Polos"
        case .sangsih: "Sangsih"
        case .together: "Together"
        }
    }

    var gloss: LocalizedStringKey {
        switch self {
        case .polos: "Plays on the beat. The steady half."
        case .sangsih: "Plays off the beat. Fills the gaps."
        case .together: "Locked in, they make one line."
        }
    }

    var hear: LocalizedStringKey {
        switch self {
        case .polos: "Hear polos"
        case .sangsih: "Hear sangsih"
        case .together: "Hear together"
        }
    }
}

/// The sample: one line, 5 6 7 6 5 4 5 6, dealt out a stroke each — polos
/// on the beat, sangsih between. Made for the guide, not one of the catalogue
/// figures: those share notes and double up (Ubitan Nyendok's polos lands
/// three times running), which is the real thing but not the idea in one look.
///
/// Key indices, as everywhere, so it plays on whatever gangsa is in use; every
/// gangsa has the bundled sound for 4 to 7 to fall back on.
enum KotekanSample {
    static let line = [5, 6, 7, 6, 5, 4, 5, 6]
    static let slots = line.count
    static let keys = 4 ... 7
    /// The catalogue's figures run at 250.
    static let strokeMs = 250

    static func key(_ half: KotekanHalf, at slot: Int) -> Int? {
        (slot % 2 == 0) == (half == .polos) ? line[slot] : nil
    }
}

/// The sample drawn on its bilah, low to high up the side, time left to
/// right: the card's half solid, the other a dashed ghost in its own colour.
/// Together joins the strokes with a thread, the one line they make. The slot
/// sounding is ringed in gold, the palette's hit.
struct KotekanSampleRoll: View {
    let voice: GuideVoice
    let slot: Int?

    var body: some View {
        Canvas { ctx, size in
            let rows = KotekanSample.keys.count
            let columns = KotekanSample.slots
            // Room round the edge for the gold ring, which stands 3pt off its
            // stroke plus its own width: fitted to the edge, the top and
            // bottom rows' rings were cut off.
            let margin: CGFloat = 6
            let cell = min(
                (size.width - margin * 2) / CGFloat(columns),
                (size.height - margin * 2) / CGFloat(rows)
            )
            let side = cell * 0.78
            let left = (size.width - cell * CGFloat(columns)) / 2
            let top = (size.height - cell * CGFloat(rows)) / 2

            func center(_ s: Int, _ key: Int) -> CGPoint {
                let row = KotekanSample.keys.upperBound - key
                return CGPoint(
                    x: left + (CGFloat(s) + 0.5) * cell,
                    y: top + (CGFloat(row) + 0.5) * cell
                )
            }

            // The bilah lanes.
            for row in 0 ..< rows {
                let y = top + (CGFloat(row) + 0.5) * cell
                ctx.fill(
                    Path(CGRect(x: left, y: y - 0.5, width: cell * CGFloat(columns), height: 1)),
                    with: .color(Theme.hairline)
                )
            }

            if voice == .together {
                var thread = Path()
                for s in 0 ..< columns {
                    let p = center(s, KotekanSample.line[s])
                    if s == 0 { thread.move(to: p) } else { thread.addLine(to: p) }
                }
                ctx.stroke(thread, with: .color(Theme.tertiary.opacity(0.35)), lineWidth: 1.5)
            }

            for s in 0 ..< columns {
                let half: KotekanHalf = s % 2 == 0 ? .polos : .sangsih
                let color = half == .polos ? Theme.polosVoice : Theme.sangsihVoice
                let p = center(s, KotekanSample.line[s])
                let rect = CGRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side)
                let block = Path(roundedRect: rect, cornerRadius: side * 0.22)
                let solid = voice.halves.contains(half)
                if solid {
                    ctx.fill(block, with: .color(color))
                } else {
                    ctx.fill(block, with: .color(color.opacity(0.08)))
                    ctx.stroke(
                        block,
                        with: .color(color.opacity(0.55)),
                        style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])
                    )
                }
                if s == slot, solid {
                    let ring = rect.insetBy(dx: -3, dy: -3)
                    ctx.stroke(
                        Path(roundedRect: ring, cornerRadius: side * 0.3),
                        with: .color(Theme.gold),
                        lineWidth: 2.5
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

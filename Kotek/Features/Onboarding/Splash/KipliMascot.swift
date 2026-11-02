//
//  KipliMascot.swift
//  Kotek
//
//  Kipli, the mascot on the splash: a barong-style head (`kipli-head`) and,
//  in front of it, its lower jaw (`kipli-mouth` — the lower teeth, tusks and
//  chin) chomping while the app loads.
//
//  The jaw moves in Core Animation, not SwiftUI, for the reason the old
//  splash's ornaments did (`Marquee`): it runs during the busiest seconds of
//  launch, and a SwiftUI animation is computed on the main thread, where the
//  loading is — so every hitch in loading would be a stammer in the mouth.
//  The render server runs this one at full rate whatever the app is doing.
//
//  But SwiftUI does NOT carry a UIKit-backed view along when it animates an
//  offset around it — the view jumps to the end — and the splash pans the
//  mascot off screen with one. So when chomping stops, the jaw eases back to
//  its rest pose in Core Animation (`settle`), and is then swapped for a plain
//  `Image` at that pose, which pans like everything else. The swap is
//  invisible: same artwork, same frame. The splash waits `settle` before it
//  pans.
//

import SwiftUI
import UIKit

struct KipliMascot: View {
    /// `LaunchLayout.unit`: the artwork is drawn at 1x in the mockup.
    let unit: CGFloat
    var chomping = true

    /// How long the jaw takes to come to rest once chomping stops. The splash
    /// holds its pan until this has passed.
    static let settle = 0.25

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The jaw is the still image now — see the header.
    @State private var still = false

    /// `kipli-head`'s own size.
    static let headSize = CGSize(width: 349, height: 281)
    /// `kipli-mouth`'s own size, and where it sits on the head at rest —
    /// matched against the mockup, in the head's units.
    private static let jawSize = CGSize(width: 149, height: 97)
    private static let jawOrigin = CGPoint(x: 100, y: 211)
    /// How far the jaw rises to shut, in the same units: the designer's closed
    /// pose, the lower teeth tucked just under the upper row and the tusks
    /// over the lip. The rest pose is the designer's open one. It used to drop
    /// BELOW rest (15, then 8) and rise only a little past it, which read as
    /// the jaw flying off the face and never closing.
    private static let jawBite: CGFloat = 24

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("kipli-head")
                .resizable()
                .frame(width: Self.headSize.width * unit, height: Self.headSize.height * unit)
            // In front of the head: the lower tusks overlap the upper lip.
            Group {
                if !still, !reduceMotion {
                    ChompingJaw(bite: Self.jawBite * unit, running: chomping, settle: Self.settle * 0.8)
                } else {
                    Image("kipli-mouth").resizable()
                }
            }
            .frame(width: Self.jawSize.width * unit, height: Self.jawSize.height * unit)
            .offset(x: Self.jawOrigin.x * unit, y: Self.jawOrigin.y * unit)
        }
        .frame(
            width: Self.headSize.width * unit,
            height: Self.headSize.height * unit,
            alignment: .topLeading
        )
        .accessibilityHidden(true)
        .task(id: chomping) {
            guard !chomping else { return }
            try? await Task.sleep(for: .seconds(Self.settle))
            still = true
        }
    }
}

/// The jaw, chomping on the render server. `bite` is how far it rises to shut.
///
/// Only the presentation moves — the layer's own transform stays identity —
/// so SwiftUI's frame on this view is never fighting a transformed layer.
private struct ChompingJaw: UIViewRepresentable {
    let bite: CGFloat
    var running: Bool
    /// Seconds to ease back to rest when `running` goes false.
    let settle: Double

    private static let key = "chomp"

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(image: UIImage(named: "kipli-mouth"))
        view.contentMode = .scaleToFill
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        let layer = view.layer
        let chomping = layer.animation(forKey: Self.key) is CAKeyframeAnimation
        // Every SwiftUI update lands here; only a real change may touch the
        // layer, or the chomp would restart from rest on each one.
        if running, !chomping {
            let chomp = CAKeyframeAnimation(keyPath: "transform.translation.y")
            // A steady chomp: from the open rest pose up to shut and back, at
            // one constant speed — no easing and no pause. The first pass was
            // two eased bites and a breath; this reads as more of a character.
            // (It then dropped below rest before shutting, as a jaw falling
            // open; that looked like it was coming off.)
            chomp.values = [0, -bite, 0]
            chomp.keyTimes = [0, 0.5, 1]
            chomp.calculationMode = .linear
            chomp.duration = 0.5
            chomp.repeatCount = .infinity
            layer.add(chomp, forKey: Self.key)
        } else if !running, chomping {
            // From wherever the bite is, back to rest — not a snap shut.
            let now = layer.presentation()?.value(forKeyPath: "transform.translation.y") as? CGFloat ?? 0
            let rest = CABasicAnimation(keyPath: "transform.translation.y")
            rest.fromValue = now
            rest.toValue = 0
            rest.duration = settle
            rest.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(rest, forKey: Self.key)
        }
    }
}

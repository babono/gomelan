//
//  Marquee.swift
//  Kotek
//
//  A picture repeated along a line and slid along it forever — the splash's
//  diagonal ornaments and the background's row of leaves — done entirely in
//  Core Animation, the way a web page would use `transform: translate`.
//
//  It used to be a SwiftUI `.offset` under a `repeatForever` animation, which
//  is NOT a GPU transform: SwiftUI works out every frame of it itself, on the
//  main thread — the same thread the splash's loading runs on — so every hitch
//  in the loading was a stutter in the ornaments. Here the picture is drawn
//  into a bitmap once, a replicator layer repeats that one texture along the
//  line, and a single translation animation is handed to the render server,
//  which runs it at the display's full rate whatever the app is doing.
//

import SwiftUI
import UIKit

struct Marquee: UIViewRepresentable {
    /// One copy, already drawn — see `Marquee.render`.
    let image: UIImage
    /// Where the first copy's top-left corner sits, in this view.
    let origin: CGPoint
    /// From one copy to the next.
    let spacing: CGVector
    /// Copies to draw, the first one place BEFORE `origin` so the start of
    /// the line is covered as it moves.
    let count: Int
    /// How far one loop slides. Equal to one repeat of the picture, so the
    /// jump back to the start lands on an identical frame.
    let travel: CGVector
    let duration: Double
    var running = true
    /// Where the whole marquee sits, as a transform about its centre — the
    /// background's rows waiting off screen, the splash's strips swung away.
    /// A change is animated over `placementDuration`, in Core Animation too:
    /// SwiftUI does not animate its own offset, scale or rotation on a view
    /// like this one, it jumps them to the end.
    var placement = CATransform3DIdentity
    var placementDuration: Double = 0
    var placementTiming: CAMediaTimingFunctionName = .easeOut

    func makeUIView(context: Context) -> MarqueeView {
        MarqueeView()
    }

    func updateUIView(_ view: MarqueeView, context: Context) {
        view.configure(self)
    }
}

final class MarqueeView: UIView {
    /// Carries `placement`. Not the view's own layer: SwiftUI sets this
    /// view's frame, and a frame on a transformed layer is undefined.
    private let stage = CALayer()
    private let replicator = CAReplicatorLayer()
    private let copy = CALayer()
    private var current: Marquee?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        replicator.addSublayer(copy)
        stage.addSublayer(replicator)
        layer.addSublayer(stage)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ next: Marquee) {
        // SwiftUI calls this on every update of the view around it; only a
        // real change may touch the layers, or the animation restarts.
        let previous = current
        current = next
        place(next, from: previous)
        if let previous, previous.image === next.image, previous.origin == next.origin,
           previous.spacing == next.spacing, previous.count == next.count,
           previous.travel == next.travel, previous.running == next.running {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        copy.contents = next.image.cgImage
        copy.contentsScale = next.image.scale
        copy.frame = CGRect(
            x: next.origin.x - next.spacing.dx,
            y: next.origin.y - next.spacing.dy,
            width: next.image.size.width,
            height: next.image.size.height
        )
        replicator.instanceCount = next.count
        replicator.instanceTransform = CATransform3DMakeTranslation(next.spacing.dx, next.spacing.dy, 0)
        CATransaction.commit()

        replicator.removeAnimation(forKey: "marquee")
        guard next.running else { return }
        let slide = CABasicAnimation(keyPath: "transform")
        slide.fromValue = CATransform3DIdentity
        slide.toValue = CATransform3DMakeTranslation(next.travel.dx, next.travel.dy, 0)
        slide.duration = next.duration
        slide.repeatCount = .infinity
        slide.timingFunction = CAMediaTimingFunction(name: .linear)
        // Kept when the app goes to the background and comes back.
        slide.isRemovedOnCompletion = false
        replicator.add(slide, forKey: "marquee")
    }

    /// The first placement is set as is; every change after is animated from
    /// wherever the stage is on screen at that moment.
    private func place(_ next: Marquee, from previous: Marquee?) {
        guard let previous else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            stage.transform = next.placement
            CATransaction.commit()
            return
        }
        guard !CATransform3DEqualToTransform(previous.placement, next.placement) else { return }
        let move = CABasicAnimation(keyPath: "transform")
        move.fromValue = stage.presentation()?.transform ?? stage.transform
        move.toValue = next.placement
        move.duration = next.placementDuration
        move.timingFunction = CAMediaTimingFunction(name: next.placementTiming)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.transform = next.placement
        CATransaction.commit()
        stage.add(move, forKey: "placement")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // `frame` is off limits on a transformed layer; bounds and position
        // are not.
        stage.bounds = bounds
        stage.position = CGPoint(x: bounds.midX, y: bounds.midY)
        replicator.frame = stage.bounds
        CATransaction.commit()
    }
}

extension Marquee {
    /// Moved by `offset`.
    static func shifted(_ offset: CGVector) -> CATransform3D {
        CATransform3DMakeTranslation(offset.dx, offset.dy, 0)
    }

    /// Turned by `degrees` (clockwise on screen) and grown by `scale` about
    /// `pivot` — a point in a view of `size` — then moved by `offset`.
    static func swung(about pivot: CGPoint, in size: CGSize, degrees: Double, scale: CGFloat,
                      then offset: CGVector) -> CATransform3D {
        // A layer transforms about its centre; this is about the pivot.
        let p = CGPoint(x: pivot.x - size.width / 2, y: pivot.y - size.height / 2)
        var t = CATransform3DMakeTranslation(-p.x, -p.y, 0)
        t = CATransform3DConcat(t, CATransform3DMakeScale(scale, scale, 1))
        t = CATransform3DConcat(t, CATransform3DMakeRotation(degrees * .pi / 180, 0, 0, 1))
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(p.x, p.y, 0))
        return CATransform3DConcat(t, CATransform3DMakeTranslation(offset.dx, offset.dy, 0))
    }
}

extension Marquee {
    /// Draws a picture once, at a size, into the bitmap a marquee repeats.
    ///
    /// Rendered at a little over the screen's own scale: on iPad the whole app
    /// is enlarged by `PadScale`, and a bitmap drawn at exactly 2x would be
    /// visibly soft once scaled up 1.3 times.
    static func render(size: CGSize, _ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UITraitCollection.current.displayScale
            * (UIDevice.current.userInterfaceIdiom == .pad ? 1.4 : 1)
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(context.cgContext)
        }
    }
}

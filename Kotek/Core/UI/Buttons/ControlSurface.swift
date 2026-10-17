//
//  ControlSurface.swift
//  Kotek
//
//  The surface behind every button, chip and menu label. Two kinds, on purpose:
//
//   - `.primary`: system Liquid Glass tinted gold at 60% (`Theme.glassFillOpacity`)
//     with dark type (`Theme.onGlassFill`). The only glass the app lets shine.
//     75% painted over the refraction, 40% with cream type let the label sink
//     into the glass.
//   - everything else: `flatGlass` — Liquid Glass with its edge cut off, tinted
//     the card brown. `.tinted` swaps the colour (record, destructive, a
//     selected chip).
//
//  History: regular glass on everything was tried first and flattened the
//  hierarchy, so secondary buttons became a flat cream wash, and after that
//  stroke-only outlines crept in at a dozen call sites, each with its own
//  height, radius and stroke opacity. The shared types put every button back on
//  ONE surface — then glass went on the secondary buttons again, in regular and
//  in clear, and both fought the theme: regular read as a system widget dropped
//  onto the ground, clear still carried the bright rim, the shadow and the
//  milky lift. A flat `.background` fill blended but was not glass at all.
//  `Glass` has no switch for the edge, so `flatGlass` draws it oversized and
//  clips it. Tint carries the hierarchy; only the main action may shine.
//
//  Views do not call this. A control a view needs is one of the components in
//  this folder, and `.swiftlint.yml` bans the surface modifiers under
//  `Features/` so a new button cannot quietly grow its own look.
//

import SwiftUI

extension View {
    /// The surface for a control's LABEL, applied after its padding and frame so
    /// the surface takes the label's own shape.
    func controlSurface(
        _ prominence: ControlProminence = .standard,
        in shape: some Shape = Capsule()
    ) -> some View {
        modifier(ControlSurface(prominence: prominence, shape: shape))
    }

    /// Liquid Glass with the edge cut off: the flat inside of the glass, none of
    /// its rim.
    ///
    /// `Glass` has no switch for the bright edge, the lensing or the shadow —
    /// they are all drawn at the shape's border — so the glass is drawn
    /// `Theme.glassBleed` past the control on every side and clipped back to its
    /// shape. What survives is the backdrop blur, the tint and the adaptive
    /// lift, which is the part that blends with the theme; the part that read as
    /// a system widget falls outside the clip.
    func flatGlass(
        tint: Color = Theme.deep.opacity(Theme.washOpacity),
        in shape: some Shape = Capsule()
    ) -> some View {
        background {
            // Glass FIRST, padding after: negative padding reports the original
            // size, so the other way round draws the glass at the control's size
            // and the rim lands inside the clip. The clip is on the glass alone,
            // so it can never cut the label.
            Color.clear
                .glassEffect(.clear.tint(tint), in: shape)
                .padding(-Theme.glassBleed)
                .clipShape(shape)
        }
    }
}

/// Reads `isEnabled` so a disabled control dims the same way everywhere. Call
/// sites used to do it by hand — `.opacity(playable ? 1 : 0.4)` — and the plain
/// button style they sat on only dimmed the label, not the surface behind it.
///
/// A disabled control also LOSES its colour. Dark type on gold at 40% opacity
/// is dark on dark and the label vanishes (Next and Play in the editor, while
/// the draft is empty); the plain surface with the ordinary type, dimmed, still
/// reads as a control that is not available. The components match it by
/// choosing their type colour on `prominence == .primary && isEnabled`.
private struct ControlSurface<S: Shape>: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    let prominence: ControlProminence
    let shape: S

    func body(content: Content) -> some View {
        Group {
            switch prominence {
            case .primary where isEnabled:
                content.glassEffect(
                    .regular.tint(Theme.buttonFill.opacity(Theme.glassFillOpacity)).interactive(),
                    in: shape
                )
            case .selected where isEnabled:
                content.background(Theme.gold, in: shape)
            case .destructive where isEnabled:
                content.flatGlass(tint: Theme.miss.opacity(Theme.tintOpacity), in: shape)
            case let .tinted(color) where isEnabled:
                content.flatGlass(tint: color.opacity(Theme.tintOpacity), in: shape)
            default:
                content.flatGlass(in: shape)
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
    }
}

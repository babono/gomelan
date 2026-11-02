//
//  PickerCard.swift
//  Kotek
//
//  The card a picker's rail is made of — a gangsa, a kotekan — in the Nawa
//  Sanga design system's look: white, and when it is the one selected, ringed
//  in gold, standing on a deeper gold edge, with a row of tumpal triangles
//  hanging from its top. "Tumpal triangles only on the selected card": they
//  are how the rail says which one is yours, so nothing else wears them.
//
//  The cards beside it are white with a faint outline and no edge. Fading
//  them is the caller's: the kotekan rail fades by distance, continuously,
//  as it scrolls.
//

import SwiftUI

extension View {
    func pickerCard(selected: Bool, tumpal: Tumpal.Size = .small, radius: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        // The tumpal goes on BEFORE the clip, so the card's own rounded
        // corners cut it — "overflow hidden". Clipped on its own strip, the
        // end teeth stood out past the corners.
        return overlay(alignment: .top) {
            if selected {
                TumpalRow(size: tumpal)
                    // Hanging from the 3pt ring's inner edge: any higher and the
                    // ring covers the red tooth at the top.
                    .padding(.top, 3)
                    .transition(.opacity)
            }
        }
        .clipShape(shape)
        .tactile(
            shape,
            fill: Theme.surface,
            outline: selected ? Theme.gold : Theme.hairline.opacity(0.6),
            outlineWidth: selected ? 3 : 1.5,
            base: selected ? Theme.gold.mix(with: Theme.merahTua, by: 0.12) : nil,
            depth: 5
        )
        .contentShape(.contextMenuPreview, shape)
        .animation(.easeOut(duration: 0.2), value: selected)
    }
}

/// The tumpal border: gold teeth, each with a Merah tooth inside it at the
/// top, as the design system draws them. The two rails differ by the inner
/// tooth — big on a gangsa card, a fleck on a kotekan card — so the two
/// pickers are told apart at a glance.
struct TumpalRow: View {
    let size: Tumpal.Size

    var body: some View {
        ZStack(alignment: .top) {
            Tumpal().fill(Theme.gold)
            Tumpal(scale: size.inner).fill(Theme.merah)
        }
        .frame(height: size.height)
        .accessibilityHidden(true)
    }
}

/// A row of downward triangles, edge to edge — the tumpal border woven along
/// the hem of a Balinese cloth.
struct Tumpal: Shape {
    enum Size {
        /// The gangsa card's: deeper teeth, the red inside nearly half.
        case large
        /// The kotekan card's: shallower, a fleck of red.
        case small

        var height: CGFloat {
            self == .large ? 11 : 8
        }

        var inner: CGFloat {
            self == .large ? 0.5 : 0.3
        }
    }

    /// About how wide each triangle is; the row is fitted to a whole number.
    var tooth: CGFloat = 12
    /// Each triangle at this fraction of its tooth, its top edge on the
    /// tooth's — the inner tooth.
    var scale: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        let count = max(1, Int((rect.width / tooth).rounded()))
        let w = rect.width / CGFloat(count)
        let tw = w * scale, th = rect.height * scale
        var path = Path()
        for i in 0 ..< count {
            let mid = rect.minX + (CGFloat(i) + 0.5) * w
            path.move(to: CGPoint(x: mid - tw / 2, y: rect.minY))
            path.addLine(to: CGPoint(x: mid + tw / 2, y: rect.minY))
            path.addLine(to: CGPoint(x: mid, y: rect.minY + th))
            path.closeSubpath()
        }
        return path
    }
}

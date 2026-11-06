//
//  NoteKeyBarsView.swift
//  Kotek
//
//  The instrument as a row of numbered bilah tiles, in the Nawa Sanga design
//  system's states:
//
//   - not heard yet: Krem, a dashed Garis outline, flat — nothing to press
//     into yet;
//   - next up: gold-tinted, standing on a Garis edge;
//   - listening: the same, ringed and glowing in gold, a waveform;
//   - ringing: solid gold, heard and being taken down;
//   - heard: Pandan on a darker green edge, ticked;
//   - a bit quiet: not heard yet's dashes with a ↻, worth doing again.
//
//  A tile whose card is open wears the gold ring too, and says where it is
//  (`InspectedTileBounds`) so the card can stand beside it.
//
//  (The first redesign pass drew the current tile orange and done tiles gold;
//  before that, a cream outline for the selected key and the hit green for
//  done.)
//

import SwiftUI

struct InspectedTileBounds: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct NoteKeyBarsView: View {
    let keyIndices: [Int]
    /// The tile that is up, if any.
    let current: Int?
    let recorded: Set<Int>
    let quiet: [Int]
    let inspected: Int?
    let phase: NoteCaptureViewModel.Phase
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(keyIndices, id: \.self) { index in
                let number = NoteCaptureViewModel.number(for: index)
                let done = recorded.contains(index)
                Button {
                    onSelect(index)
                } label: {
                    tile(number: number, look: look(of: index), ringed: index == inspected)
                        .frame(maxWidth: 72, maxHeight: 156)
                }
                // No tick: a tap plays the bilah's own sound, and the mic may be open.
                .buttonStyle(AppButtonStyle(ticks: false))
                .anchorPreference(key: InspectedTileBounds.self, value: .bounds) { index == inspected ? $0 : nil }
                .accessibilityLabel(done ? "Key \(number), recorded" : "Key \(number), not recorded")
                .accessibilityAddTraits(index == current ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }

    private enum Look { case idle, ready, listening, ringing, done, redo }

    private func look(of index: Int) -> Look {
        if index == current {
            switch phase {
            case .listening: return .listening
            case .ringing, .processing: return .ringing
            case .idle: break
            }
        }
        if quiet.contains(index) { return .redo }
        if recorded.contains(index) { return .done }
        return index == current ? .ready : .idle
    }

    @ViewBuilder
    private func tile(number: Int, look: Look, ringed: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        let dashed = look == .idle || look == .redo
        let glowing = look == .listening || ringed
        let fill: Color = switch look {
        case .idle, .redo: Theme.deep
        case .ready, .listening: Theme.kayu
        case .ringing: Theme.gold
        case .done: Theme.ok
        }
        let base: Color? = switch look {
        case .idle, .redo, .listening, .ringing: nil
        case .ready: Theme.hairline
        case .done: Theme.ok.mix(with: Theme.ireng, by: 0.55)
        }
        let ink: Color = look == .done ? Theme.onButtonFill : look == .idle ? Theme.description : Theme.cream
        VStack {
            // The cord hole a bilah hangs by.
            Circle()
                .fill(look == .done ? Theme.onButtonFill : Theme.hairline)
                .frame(width: 7, height: 7)
            Spacer()
            Group {
                switch look {
                case .listening, .ringing: Image(systemName: "waveform")
                case .done: Image(systemName: "checkmark")
                case .redo: Image(systemName: "arrow.clockwise")
                case .idle, .ready: EmptyView()
                }
            }
            .font(.symbol(18, weight: .semibold))
            Spacer()
            Text("\(number)")
                .font(.sans(16, weight: .semibold))
        }
        .foregroundStyle(ink)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tactile(
            shape,
            fill: fill,
            outline: glowing ? Theme.gold : .clear,
            outlineWidth: 2.5,
            base: base,
            depth: 4
        )
        .overlay {
            if dashed {
                shape.strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .shadow(color: glowing ? Theme.gold.opacity(0.6) : .clear, radius: 8)
        .animation(.easeOut(duration: 0.2), value: look)
    }
}

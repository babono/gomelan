//
//  NoteKeyBarsView.swift
//  Kotek
//
//  The instrument as a row of numbered bilah tiles, in the Nawa Sanga design
//  system's states:
//
//   - not heard yet: Krem, a dashed Garis outline, flat — nothing to press
//     into yet;
//   - the one you are on: standing on a Garis edge with a mic in it, or a
//     ↻ when it already has a sound and tapping Record will replace it;
//   - listening: Kayu, ringed and glowing in gold, a waveform;
//   - heard: Pandan on a darker green edge, ticked.
//
//  (The first redesign pass drew the current tile orange and done tiles gold;
//  before that, a cream outline for the selected key and the hit green for
//  done.)
//

import SwiftUI

struct NoteKeyBarsView: View {
    let keyIndices: [Int]
    let selected: Int
    let recorded: Set<Int>
    let enabled: Bool
    let onSelect: (Int) -> Void
    /// The selected key is listening: it shows a waveform for its tick.
    var listening = false

    var body: some View {
        HStack(spacing: 10) {
            ForEach(keyIndices, id: \.self) { index in
                let number = NoteCaptureViewModel.number(for: index)
                let done = recorded.contains(index)
                let current = index == selected
                Button {
                    onSelect(index)
                } label: {
                    tile(number: number, done: done, current: current)
                        .frame(maxWidth: 72, maxHeight: 180)
                }
                .buttonStyle(.appPlain)
                .disabled(!enabled)
                .accessibilityLabel(done ? "Key \(number), recorded" : "Key \(number), not recorded")
                .accessibilityAddTraits(current ? .isSelected : [])
            }
        }
    }

    private enum Look { case idle, ready, listening, done }

    @ViewBuilder
    private func tile(number: Int, done: Bool, current: Bool) -> some View {
        let look: Look = current ? (listening ? .listening : .ready) : done ? .done : .idle
        let shape = RoundedRectangle(cornerRadius: 10)
        let fill: Color = switch look {
        case .idle, .ready: Theme.deep
        case .listening: Theme.kayu
        case .done: Theme.ok
        }
        let base: Color? = switch look {
        case .idle, .listening: nil
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
                case .listening: Image(systemName: "waveform")
                case .done: Image(systemName: "checkmark")
                case .ready: Image(systemName: done ? "arrow.clockwise" : "mic")
                case .idle: EmptyView()
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
            outline: look == .listening ? Theme.gold : .clear,
            outlineWidth: 2.5,
            base: base,
            depth: 4
        )
        .overlay {
            if look == .idle {
                shape.strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .shadow(color: look == .listening ? Theme.gold.opacity(0.6) : .clear, radius: 8)
        .animation(.easeOut(duration: 0.2), value: look)
    }
}

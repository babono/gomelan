//
//  NoteKeyBarsView.swift
//  Kotek
//
//  The instrument as a row of numbered bars. The selected key is outlined, and
//  a key that already has a recording is filled.
//

import SwiftUI

struct NoteKeyBarsView: View {
    let keyIndices: [Int]
    let selected: Int
    let recorded: Set<Int>
    let enabled: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(keyIndices, id: \.self) { index in
                let number = NoteCaptureViewModel.number(for: index)
                Button {
                    onSelect(index)
                } label: {
                    RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                        .fill(recorded.contains(index) ? Theme.hit : Theme.cream.opacity(0.16))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                                .strokeBorder(Theme.cream, lineWidth: index == selected ? 4 : 0)
                        }
                        .overlay {
                            Text("\(number)")
                                .font(.sans(18, weight: .semibold))
                                .foregroundStyle(recorded.contains(index) ? Theme.onButtonFill : Theme.cream)
                        }
                        .frame(maxWidth: 72, maxHeight: 220)
                }
                .buttonStyle(.appPlain)
                .disabled(!enabled)
                .accessibilityLabel("Key \(number), \(recorded.contains(index) ? "recorded" : "not recorded")")
                .accessibilityAddTraits(index == selected ? .isSelected : [])
            }
        }
    }
}

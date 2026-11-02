//
//  AppStepper.swift
//  Kotek
//
//  A −/number/+ stepper. Big serif number, quiet Krem circles either side —
//  the shared control for key count and cycle count.
//

import SwiftUI

struct AppStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var numberSize: CGFloat = 64

    var body: some View {
        HStack(spacing: 22) {
            AppIconButton(systemImage: "minus", label: "Fewer", prominence: .quiet, size: .large) {
                value = max(range.lowerBound, value - 1)
            }
            .disabled(value <= range.lowerBound)
            Text("\(value)")
                .font(.serif(numberSize, weight: .regular))
                .foregroundStyle(Theme.cream)
                .frame(minWidth: numberSize * 1.1)
                .contentTransition(.numericText())
            AppIconButton(systemImage: "plus", label: "More", prominence: .quiet, size: .large) {
                value = min(range.upperBound, value + 1)
            }
            .disabled(value >= range.upperBound)
        }
        .animation(.snappy(duration: 0.2), value: value)
    }
}

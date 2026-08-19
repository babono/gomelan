//
//  KeyCountView.swift
//  Kotek
//
//  Setup step 1/4. How many keys does this instrument have? Asked before framing
//  because the answer decides how many bilah the later steps draw.
//
//  A pemade or kantilan usually carries ten, but practice sets and partial
//  instruments are common — and a smaller count is far quicker to calibrate — so
//  this is a question, not a constant.
//

import SwiftUI

struct KeyCountView: View {
    @Environment(AppState.self) private var app

    @State private var count: Int = 10
    private let range = 1...14

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Set up your gamelan",
                   backTitle: "Back",
                   onBack: { app.cancelInstrumentSetup() },
                   trailingText: "1 / 4")

            HStack(alignment: .center, spacing: 0) {
                // Question + explanation
                VStack(alignment: .leading, spacing: 18) {
                    Text("How many keys does your instrument have?")
                        .font(.serif(40))
                        .foregroundStyle(Theme.charcoal)
                        .fixedSize(horizontal: false, vertical: true)

                    (Text("A pemade or kantilan usually carries ten bilah — two octaves of the five-tone ")
                        + Text("pelog selisir").italic()
                        + Text(". Count the bronze keys, not the resonators."))
                        .font(.sans(15))
                        .foregroundStyle(Theme.stone)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 32)

                Rectangle().fill(Theme.charcoal.opacity(0.15)).frame(width: 1, height: 220)

                // Stepper + bilah preview + next
                VStack(spacing: 26) {
                    CountStepper(value: $count, range: range, numberSize: 76)

                    BilahBars(count: count)
                        .frame(height: 72)
                        .frame(maxWidth: 260)

                    PillButton(title: "Next", style: .outlined) {
                        app.keyCountChosen(count)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.leading, 32)
            }
            .padding(.horizontal, 40)
            .frame(maxHeight: .infinity)
        }
        .onAppear {
            if range.contains(app.profile.keyCount) { count = app.profile.keyCount }
        }
    }
}

/// The graduated bar preview — tallest/lowest on the left, echoing the gangsa
/// layout so the number has a shape, not just a digit.
private struct BilahBars: View {
    let count: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                let t = count > 1 ? Double(i) / Double(count - 1) : 0
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.charcoal.opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.charcoal.opacity(0.3), lineWidth: 1))
                    .frame(width: 14, height: 72 * (1.0 - 0.55 * t))
            }
        }
        .animation(.snappy(duration: 0.2), value: count)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

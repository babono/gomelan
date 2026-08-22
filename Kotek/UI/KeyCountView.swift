//
//  KeyCountView.swift
//  Kotek
//
//  Setup step 1/4, and the only screen a new gangsa is created from. Two facts
//  the app cannot work out for itself: what to call it, and how many keys it
//  has. The count is asked before framing because it decides how many bilah the
//  later steps draw.
//
//  A pemade or kantilan usually carries ten, but practice sets and partial
//  instruments are common — and a smaller count is far quicker to calibrate — so
//  this is a question, not a constant.
//
//  The paragraph that used to explain that (pelog selisir, count the bronze not
//  the resonators) is GONE, and the name field took its place. It was reference
//  material on a screen whose control — a stepper over a row of bars that
//  redraws as you turn it — already shows what is being counted, and anyone
//  setting up a gangsa can see how many keys it has. Naming used to happen
//  nowhere: you got "Gangsa #4" and had to go to Settings to fix it, which is a
//  poor introduction to your own instrument.
//

import SwiftUI

struct KeyCountView: View {
    @Environment(AppState.self) private var app

    @State private var count: Int = 10
    /// Held locally and committed on Next — nothing is written to disk until
    /// the whole step is done.
    @State private var name: String = ""
    @FocusState private var nameFocused: Bool
    private let range = 1...14

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Set up your gangsa",
                   backTitle: "Back",
                   onBack: { app.cancelInstrumentSetup() },
                   trailingText: "1 / 4")

            HStack(alignment: .center, spacing: 0) {
                // Question + name
                VStack(alignment: .leading, spacing: 22) {
                    Text("How many keys does your gangsa have?")
                        .font(.serif(38))
                        .foregroundStyle(Theme.charcoal)
                        .fixedSize(horizontal: false, vertical: true)

                    nameField
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
                        // Landscape keyboards cover most of the screen, so this
                        // button can be tapped while the field still holds an
                        // uncommitted edit. Drop focus first and read the draft
                        // directly rather than trusting an onSubmit that never
                        // fired.
                        nameFocused = false
                        app.keyCountChosen(count, name: name)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.leading, 32)
            }
            .padding(.horizontal, 40)
            .frame(maxHeight: .infinity)
        }
        // The keyboard eats half a landscape phone and has no Done key of its
        // own on a plain text field. Tapping the screen is the escape.
        .contentShape(Rectangle())
        .onTapGesture { nameFocused = false }
        .onAppear {
            if range.contains(app.profile.keyCount) { count = app.profile.keyCount }
            // Seeded with the generated name rather than left empty behind a
            // placeholder: it is a real, usable answer, and it shows the naming
            // pattern to anyone who would rather not think about it.
            name = app.profile.name
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Call it")
                .font(.sans(13, weight: .medium))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(Theme.stone)

            TextField("Gangsa", text: $name)
                .textFieldStyle(.plain)
                .font(.serif(24))
                .foregroundStyle(Theme.charcoal)
                .focused($nameFocused)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: 340, alignment: .leading)
                .background(Theme.deep.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: Theme.radius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius)
                        .strokeBorder(nameFocused ? Theme.buttonFill : Theme.charcoal.opacity(0.15),
                                      lineWidth: nameFocused ? 2 : 1)
                )
                .onSubmit { nameFocused = false }
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

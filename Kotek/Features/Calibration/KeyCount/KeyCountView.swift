//
//  KeyCountView.swift
//  Kotek
//
//  Setup step 1/4, and the only screen a new gangsa is created from. Two facts
//  the app cannot work out for itself: what to call it, and how many keys it
//  has. The count is asked before framing because it decides how many bilah the
//  later steps draw.
//

import SwiftUI

struct KeyCountView: View {
    @Environment(AppState.self) private var app

    @State private var count: Int = 10
    /// Held locally and committed on Next — nothing is written to disk until
    /// the whole step is done.
    @State private var name: String = ""
    @State private var type: GangsaType = .pemade
    @FocusState private var nameFocused: Bool
    private let range = 1...14

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                title: "Set up your gangsa",
                backTitle: "Back",
                onBack: { app.cancelInstrumentSetup() },
                trailingText: "1 / 4"
            )

            HStack(alignment: .center, spacing: 0) {
                // Question + name
                VStack(alignment: .leading, spacing: 22) {
                    Text("How many keys does your gangsa have?")
                        .font(.serif(38))
                        .foregroundStyle(Theme.charcoal)
                        .fixedSize(horizontal: false, vertical: true)

                    InstrumentNameField(name: $name, isFocused: $nameFocused)
                    GangsaTypePicker(selectedType: $type)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 32)

                Rectangle()
                    .fill(Theme.charcoal.opacity(0.15))
                    .frame(width: 1, height: 220)

                // Stepper + bilah preview + next
                VStack(spacing: 26) {
                    CountStepper(value: $count, range: range, numberSize: 76)

                    BilahBarsView(count: count)
                        .frame(height: 72)
                        .frame(maxWidth: 260)

                    PillButton(
                        title: "Next",
                        trailingSystemImage: "arrow.right",
                        style: .outlined
                    ) {
                        // Landscape keyboards cover most of the screen, so this
                        // button can be tapped while the field still holds an
                        // uncommitted edit. Drop focus first and read the draft
                        // directly rather than trusting an onSubmit that never
                        // fired.
                        nameFocused = false
                        app.keyCountChosen(count, name: name, type: type)
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
            type = app.profile.type
        }
    }
}

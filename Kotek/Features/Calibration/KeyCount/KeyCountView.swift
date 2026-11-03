//
//  KeyCountView.swift
//  Kotek
//
//  Setup step 1/3, and the only screen a new gangsa is created from. Two facts
//  the app cannot work out for itself: what to call it, and how many keys it
//  has. The count decides how many bilah the default key layout holds and the
//  later steps draw.
//

import SwiftUI

struct KeyCountView: View {
    @Environment(AppState.self) private var app

    @State private var count: Int = 10
    /// Held locally and committed on Next — nothing is written to disk until
    /// the whole step is done.
    @State private var name: String = ""
    /// Picked here, kept only on Next — like the name.
    @State private var photo: Data?
    @FocusState private var nameFocused: Bool
    /// No fewer than four: kotekan empat interlocks over four neighbouring
    /// bilah, so a smaller count leaves a pattern nowhere to land. It went
    /// down to one, and three made a "gangsa" the app could not teach on.
    private let range = 4 ... 14

    var body: some View {
        VStack(spacing: 0) {
            // Adding a gangsa is three steps, and says so; editing one is not.
            if app.isAddingNewInstrument {
                SetupHeader(step: 1, leadingTitle: "Cancel", onLeading: { app.cancelInstrumentSetup() })
                    .padding(.horizontal, 40)
            } else {
                TopBar(
                    title: "Set up your gangsa",
                    onBack: { app.cancelInstrumentSetup() },
                    // Slim: at full size the header alone took a fifth of a
                    // landscape phone and pushed Next off the bottom.
                    compact: true
                )
            }

            HStack(alignment: .center, spacing: 0) {
                // Kipli's question + name. The photo sits beside the name
                // rather than under it: stacked, the column ran past the
                // bottom of a landscape phone.
                VStack(alignment: .leading, spacing: 14) {
                    Text("Tell me about your gangsa")
                        .font(.serif(26))
                        .foregroundStyle(Theme.heading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .bottom, spacing: 14) {
                        InstrumentNameField(name: $name, isFocused: $nameFocused)
                        GangsaPhotoPicker(
                            image: photo.flatMap(UIImage.init) ?? InstrumentPhotoStore.image(for: app.profile),
                            onPick: { photo = $0 },
                            width: 96,
                            height: 66
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 32)

                Rectangle()
                    .fill(Theme.description.opacity(0.5))
                    .frame(width: 1, height: 170)

                // How many, as a number and as a row of bilah.
                VStack(spacing: 12) {
                    SectionLabel("How many bilah?")
                    AppStepper(value: $count, range: range, numberSize: 44)
                    BilahBarsView(count: count, height: 34)
                        .frame(height: 34)
                        .frame(maxWidth: 260)
                    Text("\(range.lowerBound) to \(range.upperBound) bilah")
                        .font(.sans(13))
                        .foregroundStyle(Theme.description)
                }
                .frame(maxWidth: .infinity)
                .padding(.leading, 32)
            }
            .padding(.horizontal, 40)
            .frame(maxHeight: .infinity)

            HStack(alignment: .bottom) {
                KipliGuide(message: "Count the bilah from one end to the other.")
                Spacer()
                AppButton(title: "Next", prominence: .primary, size: .large) {
                    // Landscape keyboards cover most of the screen, so this
                    // button can be tapped while the field still holds an
                    // uncommitted edit. Drop focus first and read the draft
                    // directly rather than trusting an onSubmit that never
                    // fired.
                    nameFocused = false
                    app.keyCountChosen(count, name: name, photo: photo)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, Theme.footerBottom)
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
}

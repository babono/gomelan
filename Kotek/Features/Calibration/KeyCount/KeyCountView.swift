//
//  KeyCountView.swift
//  Kotek
//
//  Setup step 1/2, and the only screen a new gangsa is created from. Two facts
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
    private let range = 1 ... 14

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                title: "Set up your gangsa",
                onBack: { app.cancelInstrumentSetup() },
                trailingText: "1 / 2",
                // Slim: at full size the header alone took a fifth of a
                // landscape phone and pushed Next off the bottom.
                compact: true
            )

            HStack(alignment: .center, spacing: 0) {
                // Question + name. The photo sits beside the name rather than
                // under it: stacked, the column ran past the bottom of a
                // landscape phone.
                VStack(alignment: .leading, spacing: 14) {
                    Text("How many keys does your gangsa have?")
                        .font(.serif(28))
                        .foregroundStyle(Theme.charcoal)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .bottom, spacing: 14) {
                        InstrumentNameField(name: $name, isFocused: $nameFocused)
                        GangsaPhotoPicker(
                            image: photo.flatMap(UIImage.init) ?? InstrumentPhotoStore.image(for: app.profile),
                            onPick: { photo = $0 },
                            width: 104,
                            height: 66
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 32)

                Rectangle()
                    .fill(Theme.charcoal.opacity(0.15))
                    .frame(width: 1, height: 170)

                // Stepper + bilah preview + next
                VStack(spacing: 14) {
                    CountStepper(value: $count, range: range, numberSize: 52, buttonSize: 48)

                    BilahBarsView(count: count, height: 44)
                        .frame(height: 44)
                        .frame(maxWidth: 260)

                    PillButton(
                        title: "Next",
                        style: .filled,
                        compact: true
                    ) {
                        // Landscape keyboards cover most of the screen, so this
                        // button can be tapped while the field still holds an
                        // uncommitted edit. Drop focus first and read the draft
                        // directly rather than trusting an onSubmit that never
                        // fired.
                        nameFocused = false
                        app.keyCountChosen(count, name: name, photo: photo)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.leading, 32)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 8)
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
}

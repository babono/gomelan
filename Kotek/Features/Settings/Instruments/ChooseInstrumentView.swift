//
//  ChooseInstrumentView.swift
//  Kotek
//
//  Choose which saved gamelan to play. Profiles persist key alignments and
//  strike baselines across app launches and builds.
//

import SwiftUI

struct ChooseInstrumentView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                title: "Choose your gangsa",
                onBack: { app.screen = .welcome },
                trailingText: app.savedProfiles.isEmpty
                    ? nil : "\(app.savedProfiles.count) saved",
                infoAction: { app.openGuide(.app) }
            )

            if app.savedProfiles.isEmpty {
                EmptyInstrumentsView(onAdd: { app.addNewInstrument() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                rail
            }
        }
        .onAppear {
            app.showGuideIfFirstRun(.app)

            guard let first = app.savedProfiles.first,
                  !app.savedProfiles.contains(where: { $0.id == app.profile.id })
            else { return }
            app.activateInstrument(first)
        }
    }

    // MARK: - The rail

    private var rail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(app.savedProfiles) { profile in
                    InstrumentCardView(
                        profile: profile,
                        isCurrent: app.profile.id == profile.id,
                        onSelect: { app.selectInstrument(profile) }
                    )
                }
                AddInstrumentCardView(onAdd: { app.addNewInstrument() })
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: .infinity)
    }
}

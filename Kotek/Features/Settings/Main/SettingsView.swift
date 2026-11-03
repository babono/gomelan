//
//  SettingsView.swift
//  Kotek
//
//  Settings (PRD §8): a sidebar of the player's gangsa, then the app's own
//  pages — Practice, Account, and last the dev test screens. Tempo is not
//  here: it is on the practice screen, where it changes without stopping.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        SettingsContentView(app: app)
    }
}

private struct SettingsContentView: View {
    let app: AppState
    @State private var viewModel: SettingsViewModel

    init(app: AppState) {
        self.app = app
        _viewModel = State(wrappedValue: SettingsViewModel(app: app))
    }

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            TopBar(
                title: "Settings",
                // Top right, where iOS puts Done on a sheet — Settings is
                // dismissed, not navigated back from.
                trailingTitle: "Done",
                onTrailing: { app.closeSettings() }
            )

            HStack(alignment: .top, spacing: 16) {
                sidebar
                    .frame(width: 220)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Theme.deep.opacity(0.6), in: RoundedRectangle(cornerRadius: 22))

                ScrollView {
                    page
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22)
                }
                // A new page opens at its top, not where the last one was left.
                .id(vm.page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.deep.opacity(0.6), in: RoundedRectangle(cornerRadius: 22))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .onChange(of: app.profile.id) { _, _ in
            vm.updateActiveProfileId()
        }
        .confirm(
            $vm.showDeleteConfirm,
            title: "Delete this gangsa?",
            message: LocalizedStringKey(GangsaDeletion.message(app.profile.name)),
            confirmTitle: "Delete \(app.profile.name)",
            kipli: .sad
        ) {
            vm.deleteInstrument()
        }
        .confirm(
            $vm.showDeleteAccountConfirm,
            title: "Delete your account?",
            message: "Your gangsa, records and history will be deleted from all devices. This can't be undone. Apple will ask you to confirm.",
            confirmTitle: "Delete account",
            kipli: .sad
        ) {
            vm.deleteAccount()
        }
        .confirm(
            $vm.showSignOutConfirm,
            title: "Sign out?",
            message: "Your gangsa and records will be removed from this iPhone.",
            confirmTitle: "Sign out",
            kipli: .sad
        ) {
            app.signOut()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                // Only the one being played; see `SettingsPage`.
                groupHeader("Gangsa")
                sidebarRow(.gangsa, symbol: "pianokeys", tile: Theme.keyDampened) {
                    Text(app.profile.name).lineLimit(1)
                    Spacer(minLength: 6)
                    Text("\(app.profile.keyCount)")
                        .font(.sans(12).monospacedDigit())
                        .foregroundStyle(Theme.stone)
                }

                groupHeader("App")
                // Its own key: "Practice" is also the results screen's
                // duration label, translated as that.
                sidebarRow(.practice, symbol: "metronome", tile: Theme.primary) { Text(String(
                    localized: "Settings.practice",
                    defaultValue: "Practice"
                )) }
                sidebarRow(.account, symbol: "person.fill", tile: Theme.sangsihVoice) { Text("Account") }

                // Kept reachable, last and quiet: the test screens are not
                // for most players. (The camera mode's Deprecated page sat
                // here too, until the mode went.)
                // Its own key: "More" is also the stepper's "+", "Tambah".
                groupHeader(LocalizedStringKey("Settings.more"))
                sidebarRow(.debug, symbol: "ladybug.fill", tile: Theme.stone) { Text("Debug") }
            }
            .padding(10)
        }
    }

    private func groupHeader(_ title: LocalizedStringKey) -> some View {
        SectionLabel(title, color: Theme.stone)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }

    /// A row: its symbol on a small tile in its own colour, as iOS's Settings
    /// has them — found by colour before the word is read — then the label.
    /// The open page is a plain white card; the rest sit flat on the
    /// sidebar. (It was raised too — an outline and an edge under it — which
    /// on the sidebar's own tint read as a double border.)
    private func sidebarRow(
        _ page: SettingsPage,
        symbol: String,
        tile: Color,
        @ViewBuilder label: () -> some View
    ) -> some View {
        let selected = viewModel.page == page
        return Button {
            viewModel.page = page
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.symbol(14, weight: .semibold))
                    .foregroundStyle(Theme.onButtonFill)
                    .frame(width: 28, height: 28)
                    .background(tile, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                label()
            }
            .font(.sans(15, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Theme.heading : Theme.cream.opacity(0.8))
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.appPlain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Page

    @ViewBuilder
    private var page: some View {
        switch viewModel.page {
        case .gangsa: InstrumentSectionView(viewModel: viewModel)
        case .practice: PracticeSectionView(app: app)
        case .account: AccountSectionView(viewModel: viewModel)
        case .debug: DebugSectionView(app: app)
        }
    }
}

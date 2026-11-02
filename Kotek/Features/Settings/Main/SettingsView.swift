//
//  SettingsView.swift
//  Kotek
//
//  Settings (PRD §8): a sidebar of the player's gangsa, then the app's own
//  pages — Practice, Account, and last the old camera mode and the dev test
//  screens. Tempo is not here: it is on the practice screen, where it changes
//  without stopping.
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
            confirmTitle: "Delete \(app.profile.name)"
        ) {
            vm.deleteInstrument()
        }
        .confirm(
            $vm.showDeleteAccountConfirm,
            title: "Delete your account?",
            message: "Your gangsa, records and history will be deleted from all devices. This can't be undone. Apple will ask you to confirm.",
            confirmTitle: "Delete account"
        ) {
            vm.deleteAccount()
        }
        .confirm(
            $vm.showSignOutConfirm,
            title: "Sign out?",
            message: "Your gangsa and records will be removed from this iPhone.",
            confirmTitle: "Sign out"
        ) {
            app.signOut()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                groupHeader("My gangsa")
                ForEach(app.savedProfiles) { p in
                    sidebarRow(.gangsa(p.id)) {
                        Text(p.name).lineLimit(1)
                        Spacer(minLength: 6)
                        Text("\(p.keyCount)")
                            .font(.sans(12).monospacedDigit())
                            .foregroundStyle(Theme.stone)
                    }
                }

                groupHeader("App")
                // Its own key: "Practice" is also the results screen's
                // duration label, translated as that.
                sidebarRow(.practice) { Text(String(localized: "Settings.practice", defaultValue: "Practice")) }
                sidebarRow(.account) { Text("Account") }

                // Kept reachable, last and quiet: the camera mode and the
                // test screens are not for most players.
                // Its own key: "More" is also the stepper's "+", "Tambah".
                groupHeader(LocalizedStringKey("Settings.more"))
                sidebarRow(.deprecated) { Text("Deprecated") }
                sidebarRow(.debug) { Text("Debug") }
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

    private func sidebarRow(_ page: SettingsPage, @ViewBuilder label: () -> some View) -> some View {
        let selected = viewModel.page == page
        return Button {
            viewModel.open(page)
        } label: {
            HStack(spacing: 6) { label() }
                .font(.sans(15, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.cream : Theme.cream.opacity(0.7))
                .padding(.horizontal, 10)
                .frame(minHeight: 40)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Theme.cream.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
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
        case .deprecated: DeprecatedSectionView(app: app)
        case .debug: DebugSectionView(app: app)
        }
    }
}

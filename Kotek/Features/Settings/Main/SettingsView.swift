//
//  SettingsView.swift
//  Kotek
//
//  Settings (PRD §8): account, the gangsa, judging, the old camera mode, and
//  the dev test screens. Tempo and the guide and partner voices are not here:
//  they are on the practice screen, where they change without stopping.
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

            ScrollViewReader { scroll in
                SettingsSpyRail(viewModel: vm, contentScroll: scroll)

                Rectangle()
                    .fill(Theme.cream.opacity(0.10))
                    .frame(height: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        section(.account) {
                            AccountSectionView(viewModel: vm)
                        }

                        section(.instrument) {
                            InstrumentSectionView(viewModel: vm)
                        }

                        section(.debug) {
                            DebugSectionView(app: app)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 22)
                    .padding(.bottom, vm.tailInset)
                }
                .coordinateSpace(.named(SettingsViewModel.scrollSpace))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    vm.viewport = $0
                    vm.spy()
                }
            }
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

    private func section(
        _ id: SettingsSection,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(LocalizedStringKey(viewModel.heading(for: id)))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Theme.cream.opacity(0.12), lineWidth: 1)
        )
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(SettingsViewModel.scrollSpace))
        } action: {
            viewModel.metrics.frames[id] = $0
            viewModel.spy()
        }
        .id(id)
    }
}

//
//  SettingsView.swift
//  Kotek
//
//  Settings (PRD §8): recalibrate, tempo, audio cues, detection, and dev test screens.
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
                backTitle: "Done",
                onBack: { app.closeSettings() }
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

                        section(.tempo) {
                            TempoSectionView(app: app)
                        }

                        section(.audio) {
                            AudioSectionView(app: app)
                        }

                        section(.judging) {
                            JudgingSectionView(app: app)
                        }

                        section(.camera) {
                            CameraSettingsSectionView(app: app)
                        }

                        section(.detection) {
                            DetectionSectionView(app: app)
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
            message: "Its key alignment and learned voice go with it. This cannot be undone.",
            confirmTitle: "Delete \(app.profile.name)"
        ) {
            vm.deleteInstrument()
        }
        .confirm(
            $vm.showSignOutConfirm,
            title: "Sign out?",
            message: "Your gangsa and records will be removed from this iPhone.",
            confirmTitle: "Sign out"
        ) {
            app.signOut()
        }
        .confirm(
            Binding(
                get: { app.pendingSwitch != nil },
                set: { if !$0 { app.pendingSwitch = nil } }
            ),
            title: "This Apple ID already has an account",
            message: "Switch to it? The gangsa and records on this iPhone will be removed.",
            confirmTitle: "Switch account"
        ) { [pending = app.pendingSwitch] in
            // Captured here because the dialog clears the binding — and with
            // it `pendingSwitch` — before it runs this.
            guard let pending else { return }
            Task { await app.confirmSwitch(pending) }
        }
        .busy(app.accountBusy)
    }

    private func section(
        _ id: SettingsSection,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(viewModel.heading(for: id))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(Theme.deep, in: RoundedRectangle(cornerRadius: 22))
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

//
//  SettingsSpyRail.swift
//  Kotek
//
//  Horizontal scroll-spy rail reporting where you are in Settings and providing jump shortcuts.
//

import SwiftUI

struct SettingsSpyRail: View {
    @Bindable var viewModel: SettingsViewModel
    let contentScroll: ScrollViewProxy

    var body: some View {
        ScrollViewReader { railScroll in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SettingsSection.allCases) { id in
                        chip(id)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
            }
            .onChange(of: viewModel.activeSection) { _, id in
                withAnimation(.snappy(duration: 0.25)) {
                    railScroll.scrollTo(SettingsViewModel.chipID(id), anchor: .center)
                }
            }
        }
    }

    private func chip(_ id: SettingsSection) -> some View {
        let active = id == viewModel.activeSection
        return Button {
            viewModel.jump(to: id, using: contentScroll)
        } label: {
            Text(viewModel.chipLabel(for: id))
                .font(.sans(12, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.6)
                .foregroundStyle(active ? Theme.onButtonFill : Theme.cream.opacity(0.6))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 34)
                .background(
                    active ? Theme.buttonFill : .clear,
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(active ? .clear : Theme.cream.opacity(0.18), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.kajar)
        .animation(.snappy(duration: 0.2), value: active)
        .id(SettingsViewModel.chipID(id))
    }
}

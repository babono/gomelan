//
//  CreateKotekView.swift
//  Kotek
//
//  Create Kotek: write it on the piano roll — by tapping, or by playing it on
//  the gangsa with the piezo sensors recording — then review, name and save.
//

import SwiftUI

struct CreateKotekView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        CreateKotekContentView(viewModel: CreateKotekViewModel(app: app))
    }
}

private struct CreateKotekContentView: View {
    @State var viewModel: CreateKotekViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch viewModel.step {
            case .compose: PianoRollView(viewModel: viewModel)
            case .review: ReviewKotekView(viewModel: viewModel)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.step)
        .onDisappear { viewModel.leave() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { viewModel.leave() }
        }
    }
}

// MARK: - Shared chrome

/// The bar every step shares: controls either side, a centred title.
struct CreateTopBar<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var serif = true
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(title)
                    .font(serif ? .serif(26) : .sans(16, weight: .medium))
                    .foregroundStyle(serif ? Theme.cream : Theme.cream.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(.sans(14))
                        .foregroundStyle(Theme.stone)
                }
            }
            .padding(.horizontal, 180)

            HStack(spacing: 12) {
                leading
                Spacer()
                trailing
            }
        }
        .frame(minHeight: 50)
    }
}

/// Polos / Sangsih as two pills — which half the grid writes and the sensors
/// record.
struct HalfPicker: View {
    @Binding var half: KotekanHalf
    /// False while the piano roll is writing a colotomic instrument instead:
    /// the half stays remembered but is not drawn as selected.
    var active = true

    var body: some View {
        HStack(spacing: 8) {
            pill(.polos)
            pill(.sangsih)
        }
    }

    private func pill(_ h: KotekanHalf) -> some View {
        let selected = active && half == h
        let color = h == .polos ? Theme.polosVoice : Theme.sangsihVoice
        return Button {
            half = h
        } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(h.title).font(.sans(14, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? Theme.cream : Theme.stone)
            .frame(width: 104, height: 34)
            .background(color.opacity(selected ? 0.2 : 0), in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(selected ? color : Theme.cream.opacity(0.18), lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.kajar)
    }
}

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

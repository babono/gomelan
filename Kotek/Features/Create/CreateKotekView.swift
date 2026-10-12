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

/// A round 44pt glass button holding one symbol — back, play, stop.
struct CircleIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.symbol(17, weight: .semibold))
                .foregroundStyle(Theme.cream)
                .frame(width: 44, height: 44)
                .background(Theme.cream.opacity(0.08), in: Circle())
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.gold.opacity(0.35), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.kajar)
        .accessibilityLabel(label)
    }
}

/// A capsule button with a sentence-case label. `filled` is the step's main
/// action.
struct CreateCapsuleButton: View {
    let title: String
    var filled = false
    var fullWidth = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.sans(16, weight: .semibold))
                .foregroundStyle(filled ? Theme.onButtonFill : Theme.cream)
                .lineLimit(1)
                .fixedSize(horizontal: !fullWidth, vertical: false)
                .padding(.horizontal, 24)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
                .background(filled ? Theme.buttonFill : Theme.cream.opacity(0.08), in: Capsule())
                .background(filled ? AnyShapeStyle(.clear) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                .overlay(Capsule().strokeBorder(filled ? .clear : Theme.gold.opacity(0.35), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.kajar)
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
